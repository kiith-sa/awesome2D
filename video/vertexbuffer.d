
//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Vertex buffer struct.
module video.vertexbuffer;


import video.gl2vertexbuffer;
public import video.vertexattribute;
public import video.primitivetype;


/// Vertex buffer backend struct.
///
/// Separate from VertexBuffer as templates don't work with virtual functions or
/// function pointers. While VerteBuffer provides a safe API working on custom,
/// atomic Vertex structs, the backends work on plain data (void*).
package struct VertexBufferBackend
{
    // Is the buffer locked (i.e. not modifiable)?
    bool locked_ = false;

    // Is this buffer bound for drawing?
    bool bound_ = false;

    // Number of vertices in the buffer.
    uint vertexCount_ = 0;

    // Graphics primitive type formed by the vertices of the buffer.
    PrimitiveType primitiveType_;

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
    // Pointer to bind implementation.
    void function(ref Self) bind_;
    // Pointer to release implementation.
    void function(ref Self) release_;
}

/// Vertex buffer struct.
///
/// Stores vertex data for drawing.
/// Acts as a dynamic array of vertex type V.
/// Constructed by Renderer.
///
/// The vertex type must have information about its attributes mixed in,
/// using the video.vertexattribute.VertexAttributes mixin.
///
/// Examples:
/// --------------------
/// struct TestVertex
/// {
///     vec3 Position;
///     vec2 TexCoord;
/// 
///     mixin VertexAttributes!(vec3, AttributeInterpretation.Position,
///                             vec2, AttributeInterpretation.TexCoord);
/// }
/// --------------------
///
struct VertexBuffer(V)
    if(is(V == struct))
{
package:
    /// Backend implementation of the vertex buffer. 
    ///
    /// Separate because templates and function pointers/virual functions don't
    /// work together.
    VertexBufferBackend backend_;

    /// True when any vertex buffer is bound. Avoids binding multiple vertex buffers at once.
    static bool isAVertexBufferBound_ = false;

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
        assert(!backend_.locked_, "Trying to add a vertex to a locked vertex buffer");
        backend_.addVertex_(backend_, cast(void*)(&vertex));
        ++backend_.vertexCount_;
    }

    /// Ditto.
    void addVertex(const V vertex)
    {
        assert(!backend_.locked_, "Trying to add a vertex to a locked vertex buffer");
        backend_.addVertex_(backend_, cast(void*)(&vertex));
        ++backend_.vertexCount_;
    }

    /// Lock the buffer.
    ///
    /// Must be called before binding the buffer for drawing.
    ///
    /// It is a good practice to keep a buffer locked for a long time. The
    /// backend might then be able to keep the buffer on the GPU, avoiding the
    /// need to reupload every frame.
    void lock()
    {
        backend_.locked_ = true;
        backend_.lock_(backend_);
    }

    /// Unlock the buffer.
    ///
    /// Must be called before modifying the buffer if it was locked previously.
    void unlock()
    {
        assert(!backend_.bound_, "Can't unlock a bound vertex buffer");
        backend_.unlock_(backend_);
        backend_.locked_ = false;
    } 

    /// Bind the buffer for drawing. Must be called before drawing. The buffer must be locked.
    ///
    /// Only one vertex buffer can be bound at a time. The buffer must be released before binding
    /// another buffer.
    void bind()
    {
        assert(!isAVertexBufferBound_,
               "Trying to bind a vertex buffer while another vertex buffer is bound");
        isAVertexBufferBound_ = true;
        assert(backend_.locked_, "Trying to bind an unlocked vertex buffer");
        assert(!backend_.bound_, "Trying to bind an already bound vertex buffer");
        backend_.bind_(backend_);
        backend_.bound_ = true;
    }

    /// Release the buffer after drawing.
    void release()
    {
        assert(backend_.locked_, "Vertex buffer was unlocked before releasing");
        assert(backend_.bound_,  "Trying to release a vertex buffer that is not bound");
        backend_.release_(backend_);
        backend_.bound_ = false;
        isAVertexBufferBound_ = false;
    }

    /// Is the buffer currently locked?
    @property bool locked() @safe const pure nothrow {return backend_.locked_;}

    /// Is the buffer currently bound?
    @property bool bound() @safe const pure nothrow {return backend_.bound_;}

    /// Get the number of vertices in the buffer.
    size_t length() @safe pure nothrow const {return backend_.vertexCount_;}

    /// Get the graphics primitive type formed by the vertices in the buffer.
    @property PrimitiveType primitiveType() const pure nothrow {return backend_.primitiveType_;}

    /// Construct a VertexBuffer with specified primitive type.
    ///
    /// Must NOT be called directly. Use Renderer.createVertexBuffer instead.
    ///
    /// This should only be called by Renderer and optionally by its implementations.
    /// Note that the vertex buffer backend still needs to be initialized after
    /// the vertex buffer is constructed.
    this(const PrimitiveType primitiveType)
    {
        backend_.primitiveType_ = primitiveType;
    }

    /// Get the lower bound of number of bytes taken by this struct in RAM (not VRAM).
    @property size_t memoryBytes() @safe const pure nothrow 
    {
        return this.sizeof + length * V.sizeof;
    }
}

