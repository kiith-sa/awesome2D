//          Copyright Ferdinand Majerech 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module video.uniform;


import std.traits;

import video.glslshader;


/// Convenience wrapper for a GLSL uniform variable or array.
///
/// Allows to only reupload the uniform when it's modified.
struct Uniform(Type)
{
    private:
        // Value of the uniform variable/array.
        Type value_;
        // Handle to the uniform in a GLSLShaderProgram.
        uint handle_;
        // Do we need to reupload the uniform? (e.g. after modification).
        bool needReupload_ = true;

    public:
        /// Construct a Uniform with specified handle.
        ///
        /// The handle must be returned by a GLSLShaderProgram.
        this(const uint handle) @safe pure nothrow
        {
            handle_ = handle;
        }

        /// Set the uniform's value (triggers reupload).
        @property void value(const Type rhs) @safe pure nothrow 
        {
            value_ = rhs;
            needReupload_ = true;
        }

        /// Ditto.
        @property void value(ref const Type rhs) @safe pure nothrow 
        {
            value_ = rhs;
            needReupload_ = true;
        }

        /// Access the value directly, allowing modification (triggers reupload).
        @property ref Type value() @safe pure nothrow
        {
            needReupload_ = true;
            return value_;
        }

        /// Force the uniform to be uploaded before the next draw.
        ///
        /// Should be called after a shader is bound to ensure the uniforms are uploaded.
        void reset() @safe pure nothrow
        {
            needReupload_ = true;
        }

        /// Upload the uniform to passed shader if its value has changed or it's been reset.
        ///
        /// Params:  shader = Shader this uniform belongs to. Must be the shader
        ///                   that was used to determine the uniform's handle.
        void uploadIfNeeded(GLSLShaderProgram* shader)
        {
            if(!needReupload_) {return;}
            static if(isStaticArray!Type)
            {
                shader.setUniformArray(handle_, value_);
            }
            else
            {
                shader.setUniform(handle_, value_);
            }
            needReupload_ = false;
        }
}
