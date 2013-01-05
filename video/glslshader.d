
//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// GLSL shader program.
module video.glslshader;

import derelict.opengl3.gl;
import gl3n.linalg;

import color;
import video.gl2glslshader;
import video.limits;


/// Shader program implemented in the GLSL language.
///
/// Stores function pointers to implementation functions.
///
/// Backends are implemented by setting these functions.
/// This removes one indirection compared to a virtual function call,
/// possibly making this more ARM friendly.
/// Also, might allow to share some functions between different implementations.
///
/// Note that backends might set limits on some shader properties.
///
/// All backends are required to support at least 16 vertex 
/// and 16 fragment shaders in a program (both enabled and disabled),
/// at least 16 uniforms and at least 8 attributes.
struct GLSLShaderProgram
{
package:
    union
    {
        // Data storage for the GL2 backend.
        GL2GLSLShaderData gl2_;
    }

    // Alias for readability.
    alias GLSLShaderProgram Self;

    // Pointer to the destructor implementation.
    void function(ref Self)                                  dtor_;
    // Pointer to addVertexShader implementation.
    uint function(ref Self, const string)                    addVertexShader_;
    // Pointer to addFragmentShader implementation.
    uint function(ref Self, const string)                    addFragmentShader_;
    // Pointer to lock implementation.
    void function(ref Self)                                  lock_;
    // Pointer to unlock implementation.
    void function(ref Self)                                  unlock_;
    // Pointer to enableVertexShader implementation.
    void function(ref Self, const uint)                      enableVertexShader_;
    // Pointer to disableVertexShader implementation.
    void function(ref Self, const uint)                      disableVertexShader_;
    // Pointer to bind implementation.
    void function(ref Self)                                  bind_;
    // Pointer to release implementation.
    void function(ref Self)                                  release_;
    // Pointer to getUniformHandle implementation.
    uint function(ref Self, const string)                    getUniformHandle_;
    // Pointer to setUniform float overload implementation.
    void function(ref Self, const uint, const float)         setUniformFloat_;
    // Pointer to setUniform int overload implementation.
    void function(ref Self, const uint, const int)           setUniformInt_;
    // Pointer to setUniform vec2 overload implementation.
    void function(ref Self, const uint, const vec2)          setUniformvec2_;
    // Pointer to setUniform vec3 overload implementation.
    void function(ref Self, const uint, const vec3)          setUniformvec3_;
    // Pointer to setUniform mat4 overload implementation.
    void function(ref Self, const uint, ref const(mat4))     setUniformmat4_;
    // Pointer to setUniform mat3 overload implementation.
    void function(ref Self, const uint, ref const(mat3))     setUniformmat3_;
    // Pointer to setUniform Color overload implementation.
    void function(ref Self, const uint, const Color)         setUniformColor_;
    // Pointer to getAttributeHandle implementation.
    uint function(ref Self, const string)                    getAttributeHandle_;
    // Pointer to getAttributeGLHandle implementation.
    GLint function(ref Self, const uint)                     getAttributeGLHandle_;

public:
    /// Destroy the shader program.
    ~this()
    {
        dtor_(this);
    }

    /// Add and compile a vertex shader.
    ///
    /// Can only be called while the shader program is unlocked.
    /// The added shader is enabled by default.
    ///
    /// Params: source = Source code of the shader.
    ///
    /// Returns: Handle to use to enable/disable the shader.
    ///          NOT the same as the underlying GL shader handle (location).
    ///
    /// Throws: GLSLCompileException on failure.
    uint addVertexShader(const string source)
    {
        return addVertexShader_(this, source);
    }

    /// Add and compile a fragment shader.
    ///
    /// Can only be called while the shader program is unlocked.
    /// The added shader is enabled by default.
    ///
    /// Params: source = Source code of the shader.
    ///
    /// Returns: Handle to use to enable/disable the shader.
    ///          NOT the same as the underlying GL shader handle (location).
    ///
    /// Throws: GLSLCompileException on failure.
    uint addFragmentShader(const string source)
    {
        return addFragmentShader_(this, source);
    }

    /// Lock the shader program after making changes, allowing it to be bound.
    ///
    /// This might re-link the program internally if the shaders were changed.
    ///
    /// Throws: GLSLLinkException on failure.
    void lock()
    {
        lock_(this);
    }

    /// Unlock a shader program, making modifications possible.
    ///
    /// Can't be called if the program is bound.
    void unlock()
    {
        unlock_(this);
    }

    /// Enable a vertex shader.
    ///
    /// Can only be called while the shader program is unlocked.
    ///
    /// Params: handle = Handle of the shader to enable. Must be a value 
    ///                  previously returned by addVertexShader().
    void enableVertexShader(const uint handle)
    {
        enableVertexShader_(this, handle);
    }

    /// Disable a vertex shader.
    ///
    /// Can only be called while the shader program is unlocked.
    ///
    /// Params: handle = Handle of the shader to enable. Must be a value 
    ///                  previously returned by addVertexShader().
    void disableVertexShader(const uint handle)
    {
        disableVertexShader_(this, handle);
    }

    /// Bind the shader program for drawing (also allowing uniforms to be set).
    ///
    /// Only one shader program can be bound at a time.
    ///
    /// Can only be called while the shader program is locked.
    void bind()
    {
        bind_(this);
    }

    /// Release the shader program after drawing.
    ///
    /// Invalidates any uniforms set with the program.
    ///
    /// Can only be called while the shader program is bound.
    void release()
    {
        release_(this);
    }

    /// Get a handle to a uniform variable.
    ///
    /// Params: name = Name of the uniform. Must be present in an enabled
    ///                shader - otherwise a call to setUniformValue
    ///                with the returned handle will throw.
    ///
    /// Returns: Handle to set values of the uniform with.
    ///          NOT the same as the underlying GL uniform handle (location).
    uint getUniformHandle(const string name)
    {
        return getUniformHandle_(this, name);
    }

    /// Set an integer uniform value.
    ///
    /// Can only be called while the shader program is bound.
    ///
    /// Params: handle = Handle of the uniform to set. Must be previously
    ///                  returned by getUniformHandle(), must match the
    ///                  data type of the value, and must be present in
    ///                  the shader.
    ///
    /// Throws: GLSLUniformException on failure.
    void setUniform(const uint handle, const int value)
    {
        setUniformInt_(this, handle, value);
    }

    /// Set a floating-point uniform value.
    ///
    /// Can only be called while the shader program is bound.
    ///
    /// Params: handle = Handle of the uniform to set. Must be previously
    ///                  returned by getUniformHandle(), must match the
    ///                  data type of the value, and must be present in
    ///                  the shader.
    ///
    /// Throws: GLSLUniformException on failure.
    void setUniform(const uint handle, const float value)
    {
        setUniformFloat_(this, handle, value);
    }

    /// Set a 2D vector uniform value.
    ///
    /// Can only be called while the shader program is bound.
    ///
    /// Params: handle = Handle of the uniform to set. Must be previously 
    ///                  returned by getUniformHandle(), must match the 
    ///                  data type of the value, and must be present in 
    ///                  the shader.
    ///
    /// Throws: GLSLUniformException on failure.
    void setUniform(const uint handle, const vec2 value)
    {
        setUniformvec2_(this, handle, value);
    }

    /// Set a 3D vector uniform value.
    ///
    /// Can only be called while the shader program is bound.
    ///
    /// Params: handle = Handle of the uniform to set. Must be previously 
    ///                  returned by getUniformHandle(), must match the 
    ///                  data type of the value, and must be present in 
    ///                  the shader.
    ///
    /// Throws: GLSLUniformException on failure.
    void setUniform(const uint handle, const vec3 value)
    {
        setUniformvec3_(this, handle, value);
    }

    /// Set a 4x4 matrix uniform value.
    ///
    /// Can only be called while the shader program is bound.
    ///
    /// Params: handle = Handle of the uniform to set. Must be previously 
    ///                  returned by getUniformHandle(), must match the 
    ///                  data type of the value, and must be present in 
    ///                  the shader.
    ///
    /// Throws: GLSLUniformException on failure.
    void setUniform(const uint handle, ref const(mat4) value)
    {
        setUniformmat4_(this, handle, value);
    }

    /// Set a 3x3 matrix uniform value.
    ///
    /// Can only be called while the shader program is bound.
    ///
    /// Params: handle = Handle of the uniform to set. Must be previously 
    ///                  returned by getUniformHandle(), must match the 
    ///                  data type of the value, and must be present in 
    ///                  the shader.
    ///
    /// Throws: GLSLUniformException on failure.
    void setUniform(const uint handle, ref const(mat3) value)
    {
        setUniformmat3_(this, handle, value);
    }

    /// Set a color uniform value.
    ///
    /// Can only be called while the shader program is bound.
    ///
    /// Params: handle = Handle of the uniform to set. Must be previously 
    ///                  returned by getUniformHandle(), must match the 
    ///                  data type of the value and must be present in 
    ///                  the shader.
    ///
    /// Throws: GLSLUniformException on failure.
    void setUniform(const uint handle, const Color value)
    {
        setUniformColor_(this, handle, value);
    }

package:
    /// Get a handle to a vertex attribute.
    ///
    /// Params: name = Name of the attribute. Must be present in an enabled 
    ///                shader - otherwise a call to getAttributeGLHandle
    ///                with the returned handle will throw.
    ///
    /// Returns: Handle to get the underlying GL handle with.
    ///          NOT the same as the underlying GL attribute handle (location).
    uint getAttributeOuterHandle(const string name)
    {
        return getAttributeHandle_(this, name);
    }

    /// Get the underlying GL handle (location) of the attribute.
    ///
    /// Can only be called while the shader program is bound.
    ///
    /// Called by internal Renderer code before rendering with this shader.
    /// MUST be called once for each draw - the underlying attribute 
    /// handle might change.
    ///
    /// Params: outerHandle = Outer (not underlying) handle of the attribute.
    ///                       Must be previously returned by getAttributeOuterHandle(),
    ///                       must match the data type of the attribute and must
    ///                       be present in the shader.
    ///
    /// Throws: GLSLAttributeException on failure.
    uint getAttributeGLHandle(const uint outerHandle)
    {
        return getAttributeGLHandle_(this, outerHandle);
    }
}
