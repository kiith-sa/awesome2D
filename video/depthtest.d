//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Depth test modes.
module video.depthtest;


/// Depth test modes.
enum DepthTest
{
    /// No depth test. Earlier draws are overdrawn by the later draws.
    Disabled,
    /// Read and write to the depth buffer - draws are affected by the depth buffer and change its values.
    ReadWrite
}
