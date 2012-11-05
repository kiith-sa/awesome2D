
//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


module video.gl2glslshader;

import std.conv;
import std.range;
import std.stdio;
import std.string;

import derelict.opengl.gl;

import color;
import math.vector2;
import math.matrix4;
import video.exceptions;
import video.glslshader;


/// Construct a GL2-based GLSL shader program.
void constructGLSLShaderGL2(ref GLSLShaderProgram shader) pure @safe nothrow
{
    shader.addVertexShader_      = &addShader!GL_VERTEX_SHADER;
    shader.addFragmentShader_    = &addShader!GL_FRAGMENT_SHADER;
    shader.enableVertexShader_   = &enableVertexShader;
    shader.disableVertexShader_  = &disableVertexShader;
    shader.lock_                 = &lock;
    shader.unlock_               = &unlock;
    shader.dtor_                 = &dtor;
    shader.bind_                 = &bind;
    shader.release_              = &release;
    shader.getUniformHandle_     = &getUniformHandle;
    shader.setUniformFloat_      = &setUniformFloat;
    shader.setUniformVector2f_   = &setUniformVector2f;
    shader.setUniformMatrix4f_   = &setUniformMatrix4f;
    shader.setUniformColor_      = &setUniformColor;
    shader.getAttributeHandle_   = &getAttributeHandle;
    shader.getAttributeGLHandle_ = &getAttributeGLHandle;
}

/// Data members needed by the GL2 GLSL shader program backend.
struct GL2GLSLShaderData
{
private:
    /// Single vertex or fragment shader (NOT program).
    ///
    /// This is a dumb struct; user code handles initialization/deinitialization.
    struct Shader
    {
        /// GL handle of the shader.
        GLuint handle;

        /// Is the shader enabled in the program?
        ///
        /// (used for modularity - individual shaders can be enabled/disabled.
        bool enabled;

        /// Construct a shader with specified handle. Will be enabled by default.
        this(const GLuint handle) pure nothrow @safe
        {
            this.handle = handle;
            enabled = true;
        }
    }

    /// State of the shader program.
    enum State
    {
        /// The program is unlocked for modifications.
        ///
        /// Shaders can be added, enabled or disabled.
        Unlocked,
        /// The program has been modified since last linked 
        /// (shaders added/enabled/disabled) and needs to be relinked.
        ///
        /// If the currently enabled shaders in the program match a previously
        /// linked combination, it is reused from cache.
        /// Shaders can be added, enabled or disabled.
        NeedRelink,
        /// The program has been linked and can't be modified.
        ///
        /// It can be bound for drawing.
        Locked,
        /// The program is currently bound for drawing and used by ongoing draw 
        /// calls. 
        ///
        /// Uniforms can be set and the underlying GL attribute handles can be accessed.
        Bound
    }

    /// Maximum number of vertex attributes.
    enum MAX_ATTRIBUTES = 8;
    /// Maximum number of uniform variables.
    enum MAX_UNIFORMS = 16;
    /// Maximum number of vertex shaders (enabled or disabled) in the program.
    enum MAX_VERTEX_SHADERS = 16;
    /// Maximum number of fragment shaders (enabled or disabled) in the program.
    enum MAX_FRAGMENT_SHADERS = 16;

    /// Linked GL shader program corresponding to a combination of vertex and fragment shaders.
    ///
    /// As shaders are added, enabled or disabled the shader program needs 
    /// to be relinked. To avoid linking the same shaders twice, each linked 
    /// program is stored in a cache with an ID identifying the shaders used 
    /// in the program.
    ///
    /// This is a dumb struct; user code handles initialization/deinitialization.
    struct CachedProgram
    {
        /// ID of the program.
        ///
        /// The first MAX_VERTEX_SHADERS bits specify which vertex shaders are 
        /// linked in the program. Next MAX_FRAGMENT_SHADERS bits specify
        /// fragment shaders linked.
        ulong id;
        /// GL handle of the program.
        GLuint program = 0;

        /// Translates outer (external) attribute handles to GL attribute handles for this program.
        ///
        /// Different underlying programs might have different handles for 
        /// identical attributes, so we need translation.
        GLint[MAX_ATTRIBUTES] outerToGLHandleAttribute;

        /// Translates outer (external) uniform handles to GL uniform handles for this program.
        ///
        /// Different underlying programs might have different handles for 
        /// identical uniforms, so we need translation.
        GLint[MAX_UNIFORMS]   outerToGLHandleUniform;

        /// Construct a CachedProgram with specified ID and program handle.
        this(const ulong id, const GLuint program) pure nothrow @safe
        {
            outerToGLHandleAttribute[] = 0;
            outerToGLHandleUniform[]   = 0;
            this.id      = id;
            this.program = program;
        }

        /// Is the underlying shader program null?
        @property bool isNull() const pure nothrow @safe {return program == 0;}

        /// Get the underlying GL uniform handle for specified uniform.
        ///
        /// Params:  name        = Name of the uniform to get.
        ///          outerHandle = External handle of the uniform 
        ///                        common for all cached programs.
        GLint getUniform(const string name, const uint outerHandle)
        {
            // The underlying handle for this outer handle is known, return it.
            if(outerToGLHandleUniform[outerHandle] != 0)
            {
                return outerToGLHandleUniform[outerHandle];
            }

            // On the first call, the underlying handle is not known, so 
            // get it using the name.
            GLint handle;
            handle = glGetUniformLocation(program, toStringz(name));
            if(handle == -1)
            {
                throw new GLSLUniformException("No such uniform: \"" ~ name ~ "\"");
            }

            outerToGLHandleUniform[outerHandle] = handle;
            return outerToGLHandleUniform[outerHandle];
        }

        /// Get the underlying GL attribute handle for specified attribute.
        ///
        /// Params:  name        = Name of the attribute to get.
        ///          outerHandle = External handle of the attribute
        ///                        common for all cached programs.
        GLint getAttribute(const string name, const uint outerHandle)
        {
            if(outerToGLHandleAttribute[outerHandle] != 0)
            {
                return outerToGLHandleAttribute[outerHandle];
            }

            // On the first call, the underlying handle is not known, so 
            // get it using the name.
            GLint handle;
            handle = glGetAttribLocation(program, toStringz(name));
            if(handle == -1)
            {
                throw new GLSLAttributeException("No such vertex attribute: \"" ~ name ~ "\"");
            }

            outerToGLHandleAttribute[outerHandle] = handle;
            return outerToGLHandleAttribute[outerHandle];
        }
    }

    /// Translates outer uniform handles to uniform names.
    string[] outerHandleToNameUniform_;
    /// Translates outer attribute handles to attribute names.
    string[] outerHandleToNameAttribute_;

    /// All programs (linked combinations of enabled shaders) used so far.
    CachedProgram[] programCache_;

    /// Index of the currently used shader program (uint.max if none).
    uint currentProgramIndex_ = uint.max;

    /// Vertex shaders, both enabled and disabled.
    Shader[] vertexShaders_;
    /// Fragment shaders, both enabled and disabled.
    Shader[] fragmentShaders_;

    /// Current state of the program.
    State state_ = State.Unlocked;


    /// Get the outer (independent of underlying shader program) handle to a uniform.
    ///
    /// Params:  name = Name of the uniform in source.
    ///
    /// Returns: Outer handle to the uniform, usable by user code.
    uint getUniformOuterHandle(const string name)
    {
        foreach(uint i, ref const string uniformName; outerHandleToNameUniform_)
        {
            if(uniformName == name)
            {
                return i;
            }
        }

        // New uniform - never used before. Create a new outer handle to it.
        // (The actual GL handle will only be accessed from the underlying
        // linked program at uniform upload - at that point, if the uniform
        // with specified name does not exist, we will have an error).
        assert(outerHandleToNameUniform_.length < MAX_UNIFORMS,
               "Too many uniforms (current maximum is " 
               ~ to!string(MAX_UNIFORMS) ~ ")");
        outerHandleToNameUniform_ ~= name;
        return cast(uint)(outerHandleToNameUniform_.length - 1);
    }

    /// Get the outer (independent of underlying shader program) handle to an attribute.
    ///
    /// Params:  name = Name of the attribute in source.
    ///
    /// Returns: Outer handle to the attribute, usable by user code.
    uint getAttributeOuterHandle(const string name)
    {
        foreach(uint i, ref const string attributeName; outerHandleToNameAttribute_)
        {
            if(attributeName == name)
            {
                return i;
            }
        }

        // New attribute - never used before. Create a new outer handle to it.
        // (The actual GL handle will only be accessed from the underlying
        // linked program before drawing - at that point, if the attribute
        // with specified name does not exist, we will have an error).
        assert(outerHandleToNameAttribute_.length < MAX_ATTRIBUTES,
               "Too many attributes (current maximum is " 
               ~ to!string(MAX_ATTRIBUTES) ~ ")");
        outerHandleToNameAttribute_ ~= name;
        return cast(uint)(outerHandleToNameAttribute_.length - 1);
    }

    /// Can shaders be added/enabled/disabled in the current state?
    @property bool canModifyShaders() const pure nothrow @safe
    {
        return state_ == State.Unlocked || state_ == State.NeedRelink;
    }

    /// Calculate the ID of a CachedProgram corresponding to currently enabled shaders.
    ulong calculateProgramID() const pure nothrow @safe
    {
        ulong id = 0;

        // The first MAX_VERTEX_SHADERS bits identify vertex shaders enabled,
        // the next MAX_FRAGMENT_SHADERS identify fragment shaders.

        // Attach shaders and generate ID.
        ulong pot = 1;
        foreach(ref const Shader shader; vertexShaders_) if(shader.enabled)
        {
            id |= pot;
            pot <<= 1;
        }
        pot = 1 << MAX_VERTEX_SHADERS;
        foreach(ref const Shader shader; fragmentShaders_) if(shader.enabled)
        {
            id |= pot;
            pot <<= 1;
        }

        assert(id > 0, "Locking a GLSL shader program with no shaders enabled");

        return id;
    }

    /// Get the underlying GL handle for a uniform.
    ///
    /// Should be used immediately and not stored; the handle might 
    /// become invalid the next time the shader is unlocked.
    ///
    /// Throws:  GLSLUniformException if the uniform was not found in the 
    ///          program.
    GLint getUniformGLHandle(const uint outerHandle)
    {
        CachedProgram* program = &(programCache_[currentProgramIndex_]);
        return program.getUniform(outerHandleToNameUniform_[outerHandle],
                                  outerHandle);
    }

    /// Get the underlying GL handle for a vertex attribute.
    ///
    /// Should be used immediately and not stored; the handle might 
    /// become invalid the next time the shader is unlocked.
    ///
    /// Throws:  GLSLAttributeException if the attribute was not found in the 
    ///          program.
    GLint getAttributeGLHandle(const uint outerHandle)
    {
        CachedProgram* program = &(programCache_[currentProgramIndex_]);
        return program.getAttribute(outerHandleToNameAttribute_[outerHandle],
                                    outerHandle);
    }

    /// Load and compile a shader.
    ///
    /// Params:  type   = Shader type (e.g. GL_VERTEX_SHADER).
    ///          source = Source code of the shader.
    ///
    /// Returns: GL handle to the new shader.
    ///
    /// Throws:  GLSLCompileException if the shader could not be compiled.
    static GLuint loadShader(const GLenum type, const string source)
    {
        const typeStr = type == GL_VERTEX_SHADER   ? "vertex"   : 
                        type == GL_FRAGMENT_SHADER ? "fragment" :
                                                     null;
        assert(typeStr !is null, "Unknown shader type");

        const srcLength = cast(int)source.length; 
        const srcPtr    = source.ptr;

        // Create OpenGL shader objects.
        const GLuint shader = glCreateShader(type);
        if(shader == 0)
        {
            auto msg = 
                "Could not create " ~ typeStr ~ " shader object when loading a "
                "GLSL shader. This is not the shader's fault. "
                "Most likely the graphics drivers are old.";
            throw new GLSLCompileException(msg);
        }
        scope(failure){glDeleteShader(shader);}

        // Pass shader code to OpenGL.
        glShaderSource(shader, 1, &srcPtr, &srcLength);
        auto error = glGetError();
        if(error != GL_NO_ERROR)
        {
            auto msg = "GLSL " ~ typeStr ~ "shader source uploading error. " ~
                       "Shader source: \n" ~ source;
            throw new GLSLCompileException(msg);
        }

        // Compile the shader.
        int compiled;
        glCompileShader(shader);
        glGetShaderiv(shader, GL_COMPILE_STATUS, &compiled);

        // Print any errors/warnings.
        int infoLogLength;
        glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &infoLogLength);
        static char[] infoLogBuffer;
        if(infoLogBuffer.length < infoLogLength)
        {
            infoLogBuffer.length = infoLogLength;
        }
        glGetShaderInfoLog(shader, cast(int)infoLogBuffer.length, 
                           null, infoLogBuffer.ptr);
        if(infoLogLength > 0)
        {
            writeln(infoLogBuffer[0 .. infoLogLength]);
        }

        if(!compiled)
        {
            auto msg = 
                "Couldn't compile " ~ typeStr ~ " shader due to a GLSL error. " ~ 
                "See previous program output. ";
            throw new GLSLCompileException(msg);
        }

        return shader;
    }
}

private:
/// These functions behave as OOP methods of the GL2GLSLShaderData type.
/// 
/// They implement the GLSLShader API.

/// Add a shader of specified type to the program and return its handle.
///
/// Implements GLSLShaderProgram::addVertexShader and GLSLShader::addFragmentShader.
uint addShader(GLenum type)(ref GLSLShaderProgram self, const string source) 
{with(self.gl2_)
{
    auto error = glGetError();
    if(error != GL_NO_ERROR)
    {
        writeln("GL error before loading shader: ", to!string(error));
    }

    GLuint result = loadShader(type, source);

    static if(type == GL_VERTEX_SHADER)
    {
        assert(vertexShaders_.length < MAX_VERTEX_SHADERS,
               "Too many vertex shaders in a shader program");
        vertexShaders_ ~= Shader(result);
    }
    else static if(type == GL_FRAGMENT_SHADER)
    {
        assert(fragmentShaders_.length < MAX_FRAGMENT_SHADERS,
               "Too many fragment shaders in a shader program");
        fragmentShaders_ ~= Shader(result);
    }

    return cast(uint)result;
}}

/// Destroy the shader program.
///
/// Implements GLSLShaderProgram::~this.
void dtor(ref GLSLShaderProgram self)
{with(self.gl2_)
{
    assert(state_ != State.Bound, "Forgot to release() a shader before destroying");
    // Delete all underlying shaders and programs.
    foreach(ref shader; chain(vertexShaders_, fragmentShaders_))
    {
        glDeleteShader(shader.handle);
    }
    foreach(ref program; programCache_)
    {
        assert(!program.isNull, "Trying to destroy a null cached shader program");
        glDeleteProgram(program.program);
    }
}}

/// Enable a vertex shader (do nothing if it's already enabled).
///
/// Implements GLSLShaderProgram::enableVertexShader.
void enableVertexShader(ref GLSLShaderProgram self, const uint handle)
{with(self.gl2_)
{
    assert(canModifyShaders(), 
           "Trying to enable a vertex shader after locking the shader program");
    // Find the shader and enable it.
    foreach(ref shader; vertexShaders_) if(shader.handle == handle)
    {
        if(shader.enabled){return;}
        shader.enabled = true;
        state_ = State.NeedRelink;
        return;
    }
    assert(false, 
           "Trying to enable a vertex shader not present in a shader program");
}}

/// Disable a vertex shader (do nothing if it's already disabled).
///
/// Implements GLSLShaderProgram::disableVertexShader.
void disableVertexShader(ref GLSLShaderProgram self, const uint handle)
{with(self.gl2_)
{
    assert(canModifyShaders(), 
           "Trying to disable a vertex shader after locking the shader program");
    // Find the shader and disable it.
    foreach(ref shader; vertexShaders_) if(shader.handle == handle)
    {
        if(!shader.enabled){return;}
        shader.enabled = false;
        state_ = State.NeedRelink;
        return;
    }
    assert(false, 
           "Trying to disable a vertex shader not present in a shader program");
}}

/// Lock the program, finalizing any changes, allowing it to be bound.
///
/// Implements GLSLShaderProgram::lock.
void lock(ref GLSLShaderProgram self)
{with(self.gl2_)
{
    // Already locked. Don't do anything.
    if(state_ == State.Locked || state_ == State.Bound)
    {
       writeln("Warning: locking a shader program that is already locked or bound");
       return;
    }

    // Unlocked, but not modified.
    // Just continue using the current program.
    if(state_ == State.Unlocked && currentProgramIndex_ == uint.max)
    {
        state_ = State.Locked;
        return;
    }


    // Modified. Try finding a matching program in cache, and if not found,
    // link a new program.


    // The program ID is a sequence of bits corresponding to shaders in
    // vertexShaders_ and fragmentShaders_. 1 means the shader is
    // linked in the program, 0 means it is not. The first
    // MAX_VERTEX_SHADERS bits represent vertexShaders_,
    // the next MAX_FRAGMENT_SHADERS bits represent fragmentShaders_.

    const id = calculateProgramID();
    // Try to find program with this ID. If already in cache, use it.
    foreach(uint idx, ref program; programCache_) if(program.id == id)
    {
        currentProgramIndex_ = idx;
        state_ = State.Locked;
        return;
    }

    // No such program in cache. Create a new program.
    const newProgram = glCreateProgram();
    scope(failure){glDeleteProgram(newProgram);}

    // Attach shaders to the program.
    foreach(ref shader; vertexShaders_) if(shader.enabled)
    {
        glAttachShader(newProgram, shader.handle);
    }
    foreach(ref shader; fragmentShaders_) if(shader.enabled)
    {
        glAttachShader(newProgram, shader.handle);
    }

    // Link the program.
    GLint linked;
    glLinkProgram(newProgram);
    glGetProgramiv(newProgram, GL_LINK_STATUS, &linked);

    // Write out any linking warnings or errors.
    int infoLogLength;
    glGetProgramiv(newProgram, GL_INFO_LOG_LENGTH, &infoLogLength);
    static char[] infoLogBuffer;
    if(infoLogBuffer.length < infoLogLength)
    {
        infoLogBuffer.length = infoLogLength;
    }
    glGetProgramInfoLog(newProgram, cast(int)infoLogBuffer.length, 
                        null, infoLogBuffer.ptr);
    if(infoLogLength > 0)
    {
        writeln(infoLogBuffer[0 .. infoLogLength]);
    }

    if(!linked)
    {
        throw new GLSLLinkException("Couldn't link shaders in a lock() call."
                                    "See previous program output.");
    }

    // Add the new program to cache and use it.
    programCache_ ~= CachedProgram(id, newProgram);
    currentProgramIndex_ = cast(uint)programCache_.length - 1;
}}

/// Unlock the program to allow modifications.
///
/// Implements GLSLShaderProgram::unlock.
void unlock(ref GLSLShaderProgram self)
{with(self.gl2_)
{
    final switch(state_)
    {
        case State.Unlocked:
        case State.NeedRelink:
            return;
        case State.Locked:
            state_ = State.Unlocked;
            return;
        case State.Bound:
            assert(false, "Can't unlock a bound shader program");
    }
}}

/// Bind the program for drawing (also allowing uniform upload, attribute handle access).
///
/// Implements GLSLShaderProgram::bind.
void bind(ref GLSLShaderProgram self)
{with(self.gl2_)
{
    assert(state_ == State.Locked, "Must lock a shader program before binding");
    glUseProgram(programCache_[currentProgramIndex_].program);
    state_ = State.Bound;
}}

/// Release the program after drawing.
///
/// Implements GLSLShaderProgram::release.
void release(ref GLSLShaderProgram self)
{with(self.gl2_)
{
    assert(state_ == State.Bound, "Must bind a shader program before releasing");
    glUseProgram(0);
    state_ = State.Locked;
}}

/// Get a (external, not underlying GL) handle to a uniform.
///
/// Implements GLSLShaderProgram::getUniformHandle.
uint getUniformHandle(ref GLSLShaderProgram self, const string name)
{with(self.gl2_)
{
    return getUniformOuterHandle(name);
}}

/// Set a float uniform value.
///
/// Implements GLSLShaderProgram::setUniform.
void setUniformFloat
    (ref GLSLShaderProgram self, const uint outerHandle, const float value)
{with(self.gl2_)
{
    assert(state_ == State.Bound, "Trying to set uniforms for an unbound shader program");
    glUniform1f(getUniformGLHandle(outerHandle), value);
}}

/// Set a 2D vector uniform value.
///
/// Implements GLSLShaderProgram::setUniform.
void setUniformVector2f
    (ref GLSLShaderProgram self, const uint outerHandle, const Vector2f value)
{with(self.gl2_)
{
    assert(state_ == State.Bound, "Trying to set uniforms for an unbound shader program");
    glUniform2f(getUniformGLHandle(outerHandle), value.x, value.y);
}}

/// Set a 4x4 matrix uniform value.
///
/// Implements GLSLShaderProgram::setUniform.
void setUniformMatrix4f
    (ref GLSLShaderProgram self, const uint outerHandle, ref const(Matrix4f) value)
{with(self.gl2_)
{
    assert(state_ == State.Bound, "Trying to set uniforms for an unbound shader program");
    glUniformMatrix4fv(getUniformGLHandle(outerHandle), 1, GL_FALSE, value.ptr);
}}

/// Set a color uniform value.
///
/// Implements GLSLShaderProgram::setUniform.
void setUniformColor 
    (ref GLSLShaderProgram self, const uint outerHandle, const Color value)
{with(self.gl2_)
{
    assert(state_ == State.Bound, "Trying to set uniforms for an unbound shader program");
    enum mult = 1.0f / 256.0f;
    glUniform4f(getUniformGLHandle(outerHandle),
                value.r * mult, value.g * mult, value.b * mult, value.a * mult);
}}

/// Get (external, not underlying GL) handle to an attribute. (Used by Renderer).
///
/// Implements GLSLShaderProgram::getAttributeGLHandle.
uint getAttributeHandle(ref GLSLShaderProgram self, const string name)
{with(self.gl2_)
{
    return getAttributeOuterHandle(name);
}}

/// Get underlying GL handle to an attribute. (Used by Renderer when drawing).
///
/// Implements GLSLShaderProgram::getAttributeOuterHandle.
GLint getAttributeGLHandle(ref GLSLShaderProgram self, const uint outerHandle)
{with(self.gl2_)
{
    assert(state_ == State.Bound, 
           "Trying to get the internal attribute handle for an unbound shader program");
    return getAttributeGLHandle(outerHandle);
}}
