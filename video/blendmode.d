
//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Blend mode enumeration.
module video.blendmode;


/// Enumerates blend modes (how to mix pixels from draws on top of each other).
enum BlendMode: ubyte
{
    /// No blending, new color overrides previous color.
    None,
    /// Colors of each channel are added up, clamping at maximum value 
    /// (255 for 8bit channels, 1.0 for floating-point colors)
    Add,
    /// Use alpha value of the front color for blending (0 is fully transparent, 255 or 1.0 fully opague).
    Alpha,
    /// Multiply the color channels of the back and front colors.
    Multiply
}
