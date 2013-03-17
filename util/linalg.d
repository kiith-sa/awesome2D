//          Copyright Ferdinand Majerech 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/// Various linear algebra utilities (based on gl3n)
module util.linalg;


public import gl3n.linalg;


/// Does the rectangle defined by min and max contain specified point?
///
/// Params:  min   = Minimum extents of the rectangle.
///          max   = Maximum extents of the rectangle. Both coords must be
///                  greater to equal than those in min.
///          point = Point to check for intersection with.
bool rectangleIntersectsPoint(VA, VB)(const VA min, const VA max, const VB point)
    @safe pure nothrow
    if(is(VA == vec2i) && is(VA == vec2i) || is(VA == vec2u))
{
    assert(min.x <= max.x && min.y <= max.y, "Invalid rectangle");
    return point.x >= min.x && point.x <= max.x &&
           point.y >= min.y && point.y <= max.y;
}
