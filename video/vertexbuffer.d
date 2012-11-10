
//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Vertex buffer struct.
module video.vertexbuffer;


import video.gl2vertexbuffer;


/// Vertex buffer backend struct.
///
/// Separate from VertexBuffer as templates don't work with virtual functions or
/// function pointers. While VerteBuffer provides a safe API working on custom,
/// atomic Vertex structs, the backends work on plain data (void*).
package struct VertexBufferBackend
{
    union 
    {
        // Data storage for the GL2 backend.
        GL2VertexBufferBackendData gl2_;
    }

    // Alias for readability.
    alias VertexBufferBackend Self;

    // Pointer to the destructor implementation.
    void function(ref Self) dtor_;

    // Pointer to addVertex implementation.
    void function(ref Self, const void*) addVertex_;

    // Pointer to lock implementation.
    void function(ref Self) lock_;

    // Pointer to unlock implementation.
    void function(ref Self) unlock_;
}

/// Vertex buffer struct.
///
/// Stores vertex data for drawing.
///
/// Acts as a dynamic array of vertex type V.
struct VertexBuffer(V)
{
package:
    /// Backend implementation of the vertex buffer. 
    ///
    /// Separate because templates and function pointers/virual functions don't
    /// work together.
    VertexBufferBackend backend_;

private:
    // Is the buffer locked (i.e. not modifiable)?
    bool locked_ = false;

    // Number of vertices in the buffer.
    uint vertexCount_ = 0;

    // Graphics primitive type formed by the vertices of the buffer.
    PrimitiveType primitiveType_;

public:
    /// Destroy the vertex buffer.
    ~this()
    {
        backend_.dtor_(backend_);
    }

    /// Add a vertex to the buffer. 
    ///
    /// Can only be called when the buffer is unlocked.
    void addVertex(ref const V vertex)
    {
        assert(!locked_, "Trying to add a vertex to a locked vertex buffer");
        backend_.addVertex_(cast(void*)(&backend_), vertex);
        ++vertexCount_;
    }

    /// Lock the buffer.
    ///
    /// Must be called before using the buffer for drawing.
    ///
    /// It is a good practice to keep a buffer locked for a long time. The 
    /// backend might then be able to keep the buffer on the GPU, avoiding the
    /// need to reupload every frame.
    void lock()
    {
        locked_ = true;
        backend_.lock_(backend_);
    }

    /// Unlock the buffer.
    ///
    /// Must be called before modifying the buffer if it was locked previously.
    void unlock()
    {
        backend_.unlock(backend_);
        locked_ = false;
    } 

    /// Is the buffer currently locked?
    bool locked() @safe const pure nothrow {return locked_;}

    /// Get the number of vertices in the buffer.
    uint length() @safe pure nothrow const {return vertexCount_;}

    /// Get the graphics primitive type formed by the vertices in the buffer.
    @property PrimitiveType primitiveType() const pure nothrow {return primitiveType_;}

package:
    /// Construct a VertexBuffer with specified primitive type.
    ///
    /// This should only be called by Renderer and optionally by its implementations.
    /// Note that the vertex buffer backend still needs to be initialized after
    /// the vertex buffer is constructed.
    this(const PrimitiveType primitiveType)
    {
        primitiveType_ = primitiveType;
    }
}

