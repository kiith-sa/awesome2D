//          Copyright Ferdinand Majerech 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// 3D shapes of isometric (dimetric, really) tiles.
module demo.tileshape;


import std.algorithm;


// 3D shape of a tile, used to differentiate between various slopes and flat tiles.
enum TileShape : ubyte
{
    // Flat tile (includes SW/SE cliffs.
    Flat,
    // Cliff from higher terrain at south to lower terrain at north.
    CliffN,
    // Cliff from higher terrain at north to lower terrain at south.
    CliffS,
    // Cliff from higher terrain at east to lower terrain at west.
    CliffW,
    // Cliff from higher terrain at west to lower terrain at east.
    CliffE,
    // Sloped from higher terrain at north-west to lower terrain at south-east.
    SlopeSE,
    // Sloped from higher terrain at north-east to lower terrain at south-west.
    SlopeSW,
    // Sloped from higher terrain at south-west to lower terrain at north-east.
    SlopeNE,
    // Sloped from higher terrain at south-east to lower terrain at north-west.
    SlopeNW,
    // Sloped from higher terrain at north to lower terrain at south. 
    // The slope is on the top half of the tile.
    SlopeSTop,
    // Sloped from higher terrain at south to lower terrain at north.
    // The slope is on the top half of the tile.
    SlopeNTop,
    // Sloped from higher terrain at east to lower terrain at west.
    // The slope is on the right half of the tile.
    SlopeWRight,
    // Sloped from higher terrain at west to lower terrain at east.
    // The slope is on the right half of the tile.
    SlopeERight,
    // Sloped from higher terrain at north to lower terrain at south. 
    // The slope is on the bottom half of the tile.
    SlopeSBottom,
    // Sloped from higher terrain at south to lower terrain at north.
    // The slope is on the bottom half of the tile.
    SlopeNBottom,
    // Sloped from higher terrain at east to lower terrain at west.
    // The slope is on the left half of the tile.
    SlopeWLeft,
    // Sloped from higher terrain at west to lower terrain at east.
    // The slope is on the left half of the tile.
    SlopeELeft
}

/// Strings representing tile shapes.
enum tileShapeStrings =
    ["flat",
     "slope-ne", "slope-se", "slope-nw", "slope-sw",
     "cliff-n", "cliff-s", "cliff-w", "cliff-e",
     "slope-n-top", "slope-s-top", "slope-w-right", "slope-e-right",
     "slope-n-bottom", "slope-s-bottom", "slope-w-left", "slope-e-left"];

/// Determine if a string represents a tile shape.
bool isTileShapeString(string shape) @safe pure nothrow
{
    return tileShapeStrings.canFind(shape);
}
