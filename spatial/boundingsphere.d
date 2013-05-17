//          Copyright Ferdinand Majerech 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


// A simple 3D bounding sphere.
module spatial.boundingsphere;

import util.linalg;


/// A simple 3D bounding sphere.
struct BoundingSphere
{
    /// Center of the sphere.
    vec3 center;
    /// Radius of the sphere.
    float radius = 0.0f;
}
