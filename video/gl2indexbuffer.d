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
    buffer.addIndex_ = &addIndex;
}

/// Data members of the GL2 index buffer backend.
struct GL2IndexBufferData
{
    /// Copy of the index buffer in RAM.
    /// 
    /// Used for modifications; uploaded to the IBO when lock() is called.
    uint[] indicesRAM_;
    /// IBO with the index data.
    GL2BufferObject indicesIBO_;

    /// Initialize GL2IndexBufferData.
    void initialize()
    {
        indicesIBO_ = GL2BufferObject(GL_ELEMENT_ARRAY_BUFFER);
        // Preallocate space for 16 indices.
        indicesRAM_ = allocArray!uint(16);
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
    indicesIBO_.uploadData(cast(void*)indicesRAM_, indexCount_ * uint.sizeof);
}}

/// Unlock the index buffer so it can be modified.
///
/// Implements IndexBuffer::unlock.
void unlock(ref IndexBuffer self) {with(self.gl2_) {}}

/// Add a new index to the index buffer.
///
/// Implements IndexBuffer::addVertex.
void addIndex(ref IndexBuffer self, const uint index)
{with(self) with(gl2_)
{
    assert(indexCount_ <= indicesRAM_.length,
           "There are more indices than allocated space");
    // Out of space - reallocate.
    if(indexCount_ == indicesRAM_.length)
    {
        indicesRAM_ = realloc(indicesRAM_, indicesRAM_.length * 2);
    }

    // Add the index.
    indicesRAM_[indexCount_] = index;
    // Frontend increments indexCount_.
}}
