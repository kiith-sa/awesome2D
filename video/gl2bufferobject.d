//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/// A simple GL buffer object (e.g. VBO or IBO) struct.
module video.gl2bufferobject;


import std.algorithm;

import derelict.opengl.gl;


/// A simple GL buffer object (e.g. VBO or IBO) struct.
///
/// Creates a buffer object on construction, deletes on destruction and allows uploading.
struct GL2BufferObject
{
private:
    /// Buffer object type (GL_ARRAY_BUFFER for VBO, GL_ELEMENT_ARRAY_BUFFER for IBO).
    GLenum type_;

    /// GL handle to the buffer object.
    GLuint handle_;

public:
    /// Construct a buffer object of specified type.
    this(const GLenum type)
    {
        assert([GL_ARRAY_BUFFER, GL_ELEMENT_ARRAY_BUFFER].canFind(type),
               "Unknown GL buffer object type");
        type_ = type;
        glGenBuffers(1, &handle_);
        bind();
        release();
    }

    /// Destroy the buffer object.
    ~this()
    {
        if(0 == handle_){return;}
        bind();
        // Deallocate
        glBufferData(type_, 0, null, GL_STATIC_DRAW);
        release();
        // Delete
        glDeleteBuffers(1, &handle_);
        handle_ = 0;
    }

    /// Upload data to the buffer object (overwriting any previous data).
    ///
    /// Params: data  = Pointer to the data.
    ///         bytes = Size of the data in bytes.
    void uploadData(const(void*) data, const size_t bytes)
    {
        bind();
        glBufferData(type_, bytes, data, GL_STATIC_DRAW);
        release();
    }

    /// Bind the buffer object for use in draw calls.
    void bind()
    {
        glBindBuffer(type_, handle_);
    }

    /// Release the buffer object once drawing is complete.
    void release()
    {
        glBindBuffer(type_, 0);
    }
}
