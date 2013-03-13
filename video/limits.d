//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Various graphics-related limits.
module video.limits;


package:

/// Maximum number of vertex attributes.
const MAX_ATTRIBUTES = 8;
/// Maximum number of uniform variables.
const MAX_UNIFORMS = 32;
/// Maximum number of vertex shaders (enabled or disabled) in the program.
const MAX_VERTEX_SHADERS = 16;
/// Maximum number of fragment shaders (enabled or disabled) in the program.
const MAX_FRAGMENT_SHADERS = 16;
