//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/// Graphics primitives formed by vertices at drawing.
module video.primitivetype;


/// Graphics primitives formed by vertices at drawing.
enum PrimitiveType
{
    // Consecutive vertices are paired into start-end points of lines to draw.
    Lines,
    // Consecutive vertices are grouped into triplets to form triangles to draw.
    Triangles
}
