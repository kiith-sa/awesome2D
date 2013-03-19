//          Copyright Ferdinand Majerech 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// A generic sprite.
module demo.sprite;


import std.algorithm;
import std.math;
import std.stdio;
import std.string;

import gl3n.aabb;
import gl3n.linalg;

import color;
import demo.texturepacker;
import math.math;


/// Exception throws when a sprite fails to initialize.
class SpriteInitException : Exception 
{
    public this(string msg, string file = __FILE__, int line = __LINE__)
    {
        super(msg, file, line);
    }
}

/// A generic sprite struct.
///
/// Usually composed of multiple images (different image for each facing).
///
/// Sprites may be multi-layered, e.g. with layers of data used for lighting, such as normals.
/// This is determined by the SpriteType parameter of the SpriteManager used to construct
/// the sprite. A SpriteRenderer created by the same SpriteManager must be used to render
/// the sprite.
///
/// Sprites are created by a SpriteManager and must be deleted 
/// by free() before the SpriteManager used to create them is destroyed.
struct Sprite
{
package:
    // Size of the sprite in pixels.
    vec2u size_;

    // 3D bounding box of the sprite. 
    //
    // Only valid for sprites supporting 3D lighting.
    //
    // Used by offset textures, where the minimum value for each color matches
    // the minimum value of the corresponding coordinate in the bounding box,
    // and analogously with maximum.
    AABB boundingBox_;

    // Single image of the sprite representing one direction the sprite can face.
    struct Facing
    {
        // Texture area taken up by the facing's image on its sprite page.
        TextureArea textureArea;
        // Pointer to the sprite page this facing's image is packed into.
        //
        // void* because it might be any type of sprite page.
        // The SpriteRenderer casts it to the correct type when drawing.
        void* spritePage;
        // Rotation of the facing around the Z axis in radians.
        //
        // If the sprite is drawn with this (or close) rotation, this facing will be used.
        float zRotation;
        // Offset into the index buffer of the texture page where the first 
        // index used to draw the facing's image can be found.
        uint indexBufferOffset = uint.max;

        // Is the facing validly initialized (i.e. an does its invariant hold?)?
        @property bool isValid() const pure nothrow 
        {
            return !isNaN(zRotation) && textureArea.valid && 
                   spritePage !is null && indexBufferOffset != uint.max;
        }

        // Get the lower bound of number of bytes taken by this struct in RAM (not VRAM).
        @property size_t memoryBytes() @safe const pure nothrow 
        {
            return this.sizeof;
        }
    }

    // Manually allocated array of facings.
    Facing[] facings_;

    // Name of the sprite.
    //
    // This is the parameter that was passed to loadSprite() of the SpriteManager that was
    // used to create this sprite.
    string name_;

    // Called on destruction to remove the sprite from the SpriteManager used to create it.
    //
    // Delegate is used because it might be any kind of SpriteManager.
    void delegate(Sprite*) onDestruction_;

public:
    /// Destroy the sprite.
    ///
    /// The sprite must be destroyed before the SpriteManager used to create it.
    ~this()
    {
        // Don't try to delete facings if initialization failed.
        if(facings_ !is null)
        {
            assert(onDestruction_ !is null,
                   "Sprite is initialized, but its onDestruction_ is not set");
            onDestruction_(&this);
            return;
        }
        assert(onDestruction_ is null, "Partially initialized sprite");
    }

    /// Get size of the sprite in pixels.
    @property vec2u size() @safe const pure nothrow {return size_;}

    /// Get the name of the sprite.
    @property string name() @safe const pure nothrow {return name_;}

    /// Return a reference to the bounding box of the sprite.
    @property ref const(AABB) boundingBox() @safe const pure nothrow {return boundingBox_;}

    /// Get the lower bound of number of bytes taken by this struct in RAM (not VRAM).
    @property size_t memoryBytes() @trusted const
    {
        return this.sizeof + name_.length +
               facings_.map!((ref const Facing t) => t.memoryBytes).reduce!"a + b";
    }

package:
    /// Get the index of facing closest to specified rotation value.
    uint closestFacing(vec3 rotation)
    {
        // Will probably need optimization.
        // Linear search _might_ possibly be fast enough though, and having variable 
        // number of facings is useful. 
        //
        // Maybe, if facings read from a file have a specific format 
        // (e.g. N equally separated facings where N is a power of two;
        //  we could assign indices to angles and have a function that would quickly
        //  compute which index given rotation corresponds to)
        rotation.z = rotation.z - 2.0 * PI * floor(rotation.z / (2.0 * PI));
        assert(facings_.length > 0, "A sprite with no facings");
        float minDifference = abs(facings_[0].zRotation - rotation.z);
        uint closest = 0;
        foreach(uint index, ref facing; facings_)
        {
            const difference = abs(facing.zRotation - rotation.z);
            if(difference < minDifference)
            {
                minDifference = difference;
                closest = index;
            }
        }
        return closest;
    }
}
