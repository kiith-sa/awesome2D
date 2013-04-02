
//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Index buffer struct.
module video.indexbuffer;


import video.gl2indexbuffer;


/// Index buffer struct.
///
/// Can be used with a vertex buffer to specify which vertices to draw, in what
/// order.
///
/// Indices are always 32-bit.
struct IndexBuffer
{
package:
    union 
    {
        // Data members for the GL2 backend.
        GL2IndexBufferData gl2_;
    }

    // Number of indices in the buffer.
    uint indexCount_ = 0;

    // Is the buffer locked (not modifiable)?
    bool locked_ = false;

    // Is this buffer bound for drawing?
    bool bound_ = false;

    // Alias for readability.
    alias IndexBuffer Self;

    // Pointer to the destructor implementation.
    void function(ref Self)             dtor_;
    // Pointer to the addIndex implementation.
    void function(ref Self, const uint) addIndex_;
    // Pointer to the lock implementation.
    void function(ref Self)             lock_;
    // Pointer to the unlock implementation.
    void function(ref Self)             unlock_;
    // Pointer to bind implementation.
    void function(ref Self)             bind_;
    // Pointer to release implementation.
    void function(ref Self)             release_;

    /// True when any index buffer is bound. Avoids binding multiple index buffers at once.
    static bool isAnIndexBufferBound_ = false;

public:
    /// Destroy the buffer, freeing any resources used.
    ~this()
    {
        dtor_(this);
    }

    /// Add a new index to the end of the buffer.
    ///
    /// The buffer must not be locked.
    void addIndex(const uint index)
    {
        assert(!locked, "Can't add an index to a locked index buffer");
        addIndex_(this, index);
        ++ indexCount_;
    }

    /// Lock the buffer. The buffer must be locked to be bound.
    ///
    /// When constructed, the buffer is not locked.
    void lock()
    {
        locked_ = true;
        lock_(this);
    }

    /// Unlock the buffer. Must be called to modify the buffer after drawing.
    void unlock()
    {
        assert(!bound_, "Can't unlock a bound index buffer");
        unlock_(this);
        locked_ = false;
    }

    /// Bind the buffer for drawing. Must be called before drawing. The buffer must be locked.
    ///
    /// Only one index buffer can be bound at a time. The buffer must be released before binding
    /// another buffer.
    void bind()
    {
        assert(!isAnIndexBufferBound_,
               "Trying to bind an index buffer while another index buffer is bound");
        isAnIndexBufferBound_ = true;
        assert(locked_, "Trying to bind an unlocked index buffer");
        assert(!bound_, "Trying to bind an already bound index buffer");
        bind_(this);
        bound_ = true;
    }

    /// Release the buffer after drawing.
    void release()
    {
        assert(locked_, "Index buffer was unlocked before releasing");
        assert(bound_,  "Trying to release an index buffer that is not bound");
        release_(this);
        bound_ = false;
        isAnIndexBufferBound_ = false;
    }

    /// Is the buffer locked?
    @property bool locked() @safe const pure nothrow {return locked_;}

    /// Is the buffer currently bound?
    @property bool bound() @safe const pure nothrow {return bound_;}

    /// Get the number of indices in the buffer.
    @property size_t length() @safe const pure nothrow {return indexCount_;}

    /// Get the lower bound of number of bytes taken by this struct in RAM (not VRAM).
    @property size_t memoryBytes() @safe const pure nothrow 
    {
        return this.sizeof + length * uint.sizeof;
    }
}
