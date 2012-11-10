//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// GL2 vertex buffer implementation.
module video.gl2vertexbuffer;


import derelict.opengl.gl;

import color;
import math.vector2;
import math.matrix4;
import video.gl2glslshader;
import video.vertexbuffer;


/// Construct a GL2-based vertex buffer backend.
void constructVertexBufferBackendGL2(ref VertexBufferBackend backend) @safe pure nothrow
{
    assert(false, "TODO");
}

/// Data members of the GL2 vertex buffer backend.
struct GL2VertexBufferBackendData
{
}

