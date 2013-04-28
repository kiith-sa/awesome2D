//          Copyright Ferdinand Majerech 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Main spatial management module, determining e.g. the "official" spatial manager alias.
module spatial.spatialmanager;

import spatial.quadtree;


alias QuadTree SpatialManager;

package:

/// Thrown when an object is not found in a spatial manager.
class SpatialNotFoundException : Exception 
{
    public this(string msg, string file = __FILE__, int line = __LINE__)
    {
        super(msg, file, line);
    }
}


