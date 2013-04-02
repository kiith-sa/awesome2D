//          Copyright Ferdinand Majerech 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// 3D shapes of isometric (dimetric, really) tiles.
module demo.tileshape;


import std.algorithm;
import std.math;
import std.traits;

import util.linalg;


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

/// This is the "real" world-space size of the cell, but results in graphics artifacts.
/// enum tileSize = vec3(90.88, 90.88, 36.352);

/// Size of a tile in world space.
const tileSize = vec3(90, 90, 36);

/// Size of a tile on screen (the Z value is on the Y axis together with the Y value).
const tilePixelSize = vec3u(128, 64, 32);

/// Truncate world space coords to cell coords.
///
/// Note that this just gets the part of coordinates that correspond to the 
/// position within boundaries of a cell. The actual coordinates of the cell 
/// must be calculated separately.
vec2 worldCoordsToCell(const vec2 world) @safe nothrow 
{
    // Get x,y coords within the cell.
    // We add half tile sizes as the tiles' positions are in the tiles' centers,
    // not the W corner.

    return vec2(fmod(world.x + tileSize.x * 0.5, tileSize.x),
                fmod(world.y + tileSize.y * 0.5, tileSize.y));
}

/// Describes the height and normal of the ground surface.
struct GroundDescription
{
    // Normal of the ground.
    vec3 normal;
    // Height of the ground.
    float height;
    // If true, this is a dummy GroundDescription saying there's no ground (e.g. outside of the map).
    bool noGround = false;
}

// Normal pointing upwards.
enum normalUp = vec3(0.0f, 0.0f, 1.0f);
// Normal of the SE slopes.
enum normalSlopeSE = vec3(0.3714f, 0.0f, 0.9285f);
// Normal of the SW slopes.
enum normalSlopeSW = vec3(0.0f, -0.3714f, 0.9285f);
// Normal of the NW slopes.
enum normalSlopeNW = vec3(-0.3714f, 0.0f, 0.9285f);
// Normal of the NE slopes.
enum normalSlopeNE = vec3(0.0f, 0.3714f, 0.9285f);
// Normal of the S slopes.
enum normalSlopeS  = vec3(0.3482f, -0.3482f, 0.8703f);
// Normal of the N slopes.
enum normalSlopeN  = vec3(-0.3482f, 0.3482f, 0.8703f);
// Normal of the E slopes.
enum normalSlopeE  = vec3(0.3482f, 0.3482f, 0.8703f);
// Normal of the W slopes.
enum normalSlopeW  = vec3(-0.3482f, -0.3482f, 0.8703f);

/// An array of function calculating surface height/normal depending on coordinates within a tile.
///
/// The array is indexed by TileShape the function calculates height for.
/// The function parameters are world-space X and Y coordinates, _relative_ to 
/// the tile.
GroundDescription function(vec2) @safe [] tileHeightFunctions;

/// Initialize tileHeightFunctions.
static this()
{
    static const xMax = tileSize.x;
    static const yMax = tileSize.y;
    static const zMax = tileSize.z;

    tileHeightFunctions.length = EnumMembers!TileShape.length;
    // Note: the area on top of a cliff/slope always includes the 
    // case where the compared values are equal.
    // (E.g; in CliffN, x == y is on top of the cliff)
    tileHeightFunctions[TileShape.Flat] =
        (vec2 xy)
        {assert(false, 
                "tileHeightFunctions[TileShape.Flat] called - "
                "should be special cased for speed instead");};
    tileHeightFunctions[TileShape.CliffN] = 
        (vec2 xy)
        {
            // N is (-1,1) vector.
            // the area where y > x is below the cliff.
            // the x <= y is on the cliff.
            return GroundDescription(normalUp, xy.y > xy.x ? 0.0f : zMax);
        };
    tileHeightFunctions[TileShape.CliffS] = 
        (vec2 xy)
        {
            // S is (1,-1) vector.
            // the area where y < x is below the cliff.
            // the x >= y is on the cliff.
            return GroundDescription(normalUp, xy.x > xy.y ? 0.0f : zMax);
        };
    tileHeightFunctions[TileShape.CliffE] = 
        (vec2 xy)
        {
            // E is (1,1) vector.
            // the area where y > tileSize.x - x is below the cliff.
            // the y <= tileSize.x - x is on the cliff.
            return GroundDescription(normalUp, xy.y > xMax - xy.x ? 0.0f : zMax);
        };
    tileHeightFunctions[TileShape.CliffW] = 
        (vec2 xy)
        {
            // W is (-1,-1) vector.
            // the area where y < tileSize.x - x is below the cliff.
            // the y >= tileSize.x - x is on the cliff.
            return GroundDescription(normalUp, xy.y < xMax - xy.x ? 0.0f : zMax);
        };
    tileHeightFunctions[TileShape.SlopeSE] = 
        (vec2 xy)
        {
            // SE is (1,0) vector.
            // Height decreases as x increases.
            return GroundDescription(normalSlopeSE, zMax * (1.0f - xy.x / xMax));
        };
    tileHeightFunctions[TileShape.SlopeSW] = 
        (vec2 xy)
        {
            // SW is (0,-1) vector.
            // Height increases as y increases.
            return GroundDescription(normalSlopeSW, zMax * (xy.y / yMax));
        };
    tileHeightFunctions[TileShape.SlopeNE] = 
        (vec2 xy)
        {
            // NE is (0,1) vector.
            // Height descreases as y increases.
            return GroundDescription(normalSlopeNE, zMax * (1.0f - xy.y / yMax));
        };
    tileHeightFunctions[TileShape.SlopeNW] = 
        (vec2 xy)
        {
            // NW is (-1,0) vector.
            // Height increases as x increases.
            return GroundDescription(normalSlopeNW, zMax * (xy.x / xMax));
        };

    static const halfDiagonal = sqrt(xMax * xMax + yMax * yMax) * 0.5;
    // Not sure if these slopes' height functions are correct.
    tileHeightFunctions[TileShape.SlopeSTop] = 
        (vec2 xy)
        {
            const diff = abs(xy.x - xy.y);
            // S is (1,-1) vector.
            // Height increases with distance from line y = x
            // in the northern half of the tile.
            const z = xy.y < xy.x ? 0.0f : zMax * (sqrt(2 * diff * diff) * 0.5f) / halfDiagonal;
            return GroundDescription(normalSlopeS, z);
        };
    tileHeightFunctions[TileShape.SlopeSBottom] = 
        (vec2 xy)
        {
            const diff = abs(xy.x - xy.y);
            // S is (1,-1) vector.
            // Height decreases with distance from line y = x
            // in the southern half of the tile.
            const z = xy.y >= xy.x ? 1.0f : zMax * (1.0f - sqrt(2 * diff * diff) * 0.5f) / halfDiagonal;
            return GroundDescription(normalSlopeS, z);
        };
    tileHeightFunctions[TileShape.SlopeNTop] = 
        (vec2 xy)
        {
            const diff = abs(xy.x - xy.y);
            // N is (-1,1) vector.
            // Height decreases with distance from line y = x
            // in the northern half of the tile.
            const z = xy.y <= xy.x ? 1.0f : zMax * (1.0f - (sqrt(2 * diff * diff) * 0.5f) / halfDiagonal);
            return GroundDescription(normalSlopeN, z);
        };
    tileHeightFunctions[TileShape.SlopeNBottom] = 
        (vec2 xy)
        {
            const diff = abs(xy.x - xy.y);
            // N is (-1,1) vector.
            // Height increases with distance from line y = x
            // in the southern half of the tile.
            const z = xy.y > xy.x ? 0.0f : zMax * (sqrt(2 * diff * diff) * 0.5f) / halfDiagonal;
            return GroundDescription(normalSlopeN, z);
        };
    tileHeightFunctions[TileShape.SlopeWRight] = 
        (vec2 xy)
        {
            const sqSize = xMax - xy.y - xy.x;
            // W is (-1,-1) vector.
            // Height increases with distance from line y = xMax - x
            // in the eastern half of the tile.
            const z = xy.y < xMax - xy.x ? 0.0f : zMax * (sqrt(2 * sqSize * sqSize) * 0.5f) / halfDiagonal;
            return GroundDescription(normalSlopeW, z);
        };
    tileHeightFunctions[TileShape.SlopeWLeft] = 
        (vec2 xy)
        {
            const sqSize = xMax - xy.y - xy.x;
            // W is (-1,-1) vector.
            // Height decreases with distance from line y = xMax - x
            // in the western half of the tile.
            const z = xy.y >= xMax - xy.x ? 1.0f : zMax * (1.0f - (sqrt(2 * sqSize * sqSize) * 0.5f) / halfDiagonal);
            return GroundDescription(normalSlopeW, z);
        };
    tileHeightFunctions[TileShape.SlopeERight] = 
        (vec2 xy)
        {
            const sqSize = xMax - xy.y - xy.x;
            // E is (1,1) vector.
            // Height decreases with distance from line y = xMax - x
            // in the eastern half of the tile.
            const z = xy.y <= xMax - xy.x ? 1.0f : zMax * (1.0f - (sqrt(2 * sqSize * sqSize) * 0.5f) / halfDiagonal);
            return GroundDescription(normalSlopeE, z);
        };
    tileHeightFunctions[TileShape.SlopeELeft] = 
        (vec2 xy)
        {
            const sqSize = xMax - xy.y - xy.x;
            // E is (1,1) vector.
            // Height increases with distance from line y = xMax - x
            // in the western half of the tile.
            const z = xy.y > xMax - xy.x ? 0.0f : zMax * (sqrt(2 * sqSize * sqSize) * 0.5f) / halfDiagonal;
            return GroundDescription(normalSlopeE, z);
        };
}
