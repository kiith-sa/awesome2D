//          Copyright Ferdinand Majerech 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/// Vertex type used to draw sprites.
module demo.spritevertex;


import video.vertexbuffer;

import gl3n.linalg;


/// Vertex type used to draw sprites.
struct SpriteVertex
{
    // Position of the vertex.
    vec2 position;
    // Texture coordinate of the vertex.
    vec2 texCoord;

    // Metadata for Renderer.
    mixin VertexAttributes!(vec2, AttributeInterpretation.Position,
                            vec2, AttributeInterpretation.TexCoord);
}
