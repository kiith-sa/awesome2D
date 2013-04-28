//          Copyright Ferdinand Majerech 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// A 2D (bounding) square specified by center and half size.
module spatial.centeredsquare;


import std.math;

import util.linalg;


/// A 2D (bounding) square specified by center and half size.
struct CenteredSquare
{
    /// Center of the square.
    vec2 center;
    /// Half-size of the square ("radius").
    float halfSize;

    /// Does this square fully contain the other square?
    bool contains(const CenteredSquare rhs)
        @safe pure nothrow const
    {
        return ((abs(rhs.center.x - center.x) + rhs.halfSize) < halfSize) && 
               ((abs(rhs.center.y - center.y) + rhs.halfSize) < halfSize);
    }

    /// Does this square intersect with the other square?
    bool intersects(const CenteredSquare rhs)
        @safe pure nothrow const
    {
        const intersectDistance = rhs.halfSize + halfSize;
        return intersectDistance >= abs(rhs.center.x - center.x) && 
               intersectDistance >= abs(rhs.center.y - center.y);
    }
}
