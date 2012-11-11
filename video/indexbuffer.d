
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

    // Is the buffer locked (ready for drawing)?
    bool locked_ = false;

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

    /// Lock the buffer. The buffer must be locked for drawing.
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
        unlock_(this);
        locked_ = false;
    }

    /// Is the buffer locked?
    @property bool locked() const pure nothrow {return locked_;}

    /// Get the number of indices in the buffer.
    @property size_t length() const pure nothrow {return indexCount_;}
}
