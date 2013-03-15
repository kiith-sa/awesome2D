//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// GL2 index buffer backend.
module video.gl2indexbuffer;


import derelict.opengl3.gl;

import memory.memory;
import video.gl2bufferobject;
import video.indexbuffer;


/// Construct a GL2-based index buffer.
void constructIndexBufferGL2(ref IndexBuffer buffer)
{
    buffer.gl2_  = GL2IndexBufferData.init;
    buffer.gl2_.initialize();
    buffer.dtor_     = &dtor;
    buffer.lock_     = &lock;
    buffer.unlock_   = &unlock;
    buffer.bind_     = &bind;
    buffer.release_  = &release;
    buffer.addIndex_ = &addIndex;
}

/// Data members of the GL2 index buffer backend.
///
/// We use ushort indices from start, and if a too large index is added, we
/// reallocate and use uints.
struct GL2IndexBufferData
{
    /// Data type of indices in the buffer.
    GLenum indexType_ = GL_UNSIGNED_SHORT;
    /// Size of one index in bytes.
    uint indexBytes_  = ushort.sizeof;
    /// Copy of the index buffer in RAM.
    /// 
    /// Used for modifications; uploaded to the IBO when lock() is called.
    ubyte[] indicesRAM_;
    /// IBO with the index data.
    GL2BufferObject indicesIBO_;

    /// Initialize GL2IndexBufferData.
    void initialize()
    {
        indicesIBO_ = GL2BufferObject(GL_ELEMENT_ARRAY_BUFFER);
        // Preallocate space for 32 indices.
        indicesRAM_ = allocArray!ubyte(64);
    }

    /// Deinitialize, freeing all used resources.
    void deinitialize()
    {
        free(indicesRAM_);
        clear(indicesIBO_);
    }
}


private:

/// Destroy the index buffer.
///
/// Implements IndexBuffer::~this.
void dtor(ref IndexBuffer self)
{with(self.gl2_)
{
    deinitialize();
}}

/// Lock the index buffer so it can be used in draw calls.
///
/// Implements IndexBuffer::lock.
void lock(ref IndexBuffer self)
{with(self) with(gl2_)
{
    indicesIBO_.uploadData(cast(void*)indicesRAM_, indexCount_ * indexBytes_);
}}

/// Unlock the index buffer so it can be modified.
///
/// Implements IndexBuffer::unlock.
void unlock(ref IndexBuffer self) {with(self.gl2_) {}}

/// Bind the index buffer so it can be drawn.
///
/// Implements IndexBuffer::bind.
void bind(ref IndexBuffer self)
{with(self) with(gl2_)
{
    indicesIBO_.bind();
}}

/// Release the vertex buffer after drawing.
///
/// Implements IndexBuffer::release.
void release(ref IndexBuffer self) 
{with(self) with(gl2_)
{
    indicesIBO_.release();
}}


/// Add a new index to the index buffer.
///
/// Implements IndexBuffer::addVertex.
void addIndex(ref IndexBuffer self, const uint index)
{with(self) with(gl2_)
{
    assert(indexCount_ * indexBytes_ <= indicesRAM_.length,
           "There are more indices than allocated space");
    // Out of space - reallocate.
    if(indexCount_ * indexBytes_ == indicesRAM_.length)
    {
        indicesRAM_ = realloc(indicesRAM_, indicesRAM_.length * 2);
    }

    // The index can't be represented by ushorts, so use uints.
    if(indexType_ == GL_UNSIGNED_SHORT && index > ushort.max)
    {
        indexType_ = GL_UNSIGNED_INT;
        indexBytes_ = uint.sizeof;
        auto oldIndicesRAM = indicesRAM_;
        indicesRAM_ = allocArray!ubyte(indicesRAM_.length * 2);
        foreach(i; 0 .. indexCount_)
        {
            (cast(uint[])indicesRAM_)[i] = (cast(ushort[])oldIndicesRAM)[i];
        }
        free(oldIndicesRAM);
    }

    // Add the index.
    if(indexType_ == GL_UNSIGNED_SHORT)
    {
        (cast(ushort[])indicesRAM_)[indexCount_] = cast(ushort)index;
    }
    else if(indexType_ == GL_UNSIGNED_INT)
    {
        (cast(uint[])indicesRAM_)[indexCount_] = index;
    }
    else
    {
        assert(false, "Unknown index type");
    }
    // Frontend increments indexCount_.
}}
