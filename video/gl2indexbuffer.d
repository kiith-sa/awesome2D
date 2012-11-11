//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// GL2 index buffer backend.
module video.gl2indexbuffer;


import video.indexbuffer;


/// Construct a GL2-based index buffer.
void constructIndexBufferGL2(ref IndexBuffer buffer) @safe pure nothrow
{
    buffer.gl2_ = GL2IndexBufferData.init;
}

/// Data members of the GL2 index buffer backend.
struct GL2IndexBufferData
{
}
