//          Copyright Ferdinand Majerech 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// A large 3-layer texture whose space is partitioned into smaller areas used to store sprites.
module demo.spritepage;


import std.conv;

import gl3n.linalg;

import color;
import demo.texturepacker;
import image;
import math.math;
import memory.memory;
import video.renderer;
import video.texture;


/// Enumerates the texture units used by sprite layers.
enum SpriteTextureUnit 
{
    /// Diffuse color texture unit.
    Diffuse = 0,
    /// Normal texture unit.
    Normal = 1,
    /// Offset texture unit.
    Offset = 2
}

/// A large 3-layer texture whose space is partitioned into smaller areas used to store sprites.
///
/// Most sprites consist of relatively small, non-power-of-two images. These are packed
/// into a larger, power-of-two sized image in the sprite page. The image is composed 
/// of 3 textures of same size - layers, storing diffuse color, normals and offsets.
/// This allows to draw many sprites without constantly swapping textures, greatly 
/// improving performance.
///
/// A sprite page supports adding and removing images. Adding might fail if there is
/// not enough space, in which case a different sprite page must be used.
///
/// The TexturePacker type parameter allows to easily replace texture packer algorithms
/// if needed.
struct GenericSpritePage(TexturePacker)
{
private:
    // Diffuse color layer of the page.
    Texture* diffuseTexture_;
    // Normal layer of the page.
    //
    // The normals are encoded to RGB colors by R representing the X component of 
    // the normal, G representing Y and B representing Z. The lowest color value 
    // maps to -1 for the vector component, the highest to +1.
    Texture* normalTexture_;
    // Position offset texture layer of the page.
    //
    // Colors of this texture represent positions within the sprite's bounding box.
    // R is the X coordinate, G is Y, and B is Z. The minimum value 
    // (0) maps to the minimum value of the coordinate in the bounding box,
    // while the maximum (255 or 1.0) is the maximum value.
    Texture* offsetTexture_;
    // Size of the texture page in pixels.
    vec2u size_;
    // Set to true when createSpritePage succeeds.
    //
    // Used to avoid destructor cleaning up uninitialized members.
    bool initialized_ = false;
    // Handles packing of images to the page's texture space.
    TexturePacker packer_;

public:
    /// Destroy the SpritePage. The page must be empty.
    ~this()
    {
        assert(empty, "Trying to destroy a sprite page that is not empty");

        if(initialized_)
        {
            free(diffuseTexture_);
            free(normalTexture_);
            free(offsetTexture_);
        }
    }

    /// Bind the page's textures for drawing.
    void bind()
    {
        diffuseTexture_.bind(SpriteTextureUnit.Diffuse);
        normalTexture_.bind(SpriteTextureUnit.Normal);
        offsetTexture_.bind(SpriteTextureUnit.Offset);
    }

    /// Insert an image (part of a sprite) into the page.
    ///
    /// All layers must have the same size. The diffuse layer must be in RGBA_8
    /// color format, the normal and offset layers must be RGB_8.
    ///
    /// Params:  diffuse = Diffuse color layer of the image.
    ///          normal  = Normal layer of the image.
    ///          offset  = Offset layer of the image.
    ///
    /// Returns: Texture area the image takes up on the page.
    ///          If the image could not be inserted, the area is invalid
    ///          (must be checked by TextureArea.valid).
    TextureArea insertImage(ref const Image diffuse, ref const Image normal, 
                            ref const Image offset)
    {
        const size = diffuse.size;
        assert(size == normal.size && size == offset.size,
               "Sizes of image layers are not identical");
        assert(diffuse.format == ColorFormat.RGBA_8 && 
               normal.format  == ColorFormat.RGB_8 &&
               offset.format  == ColorFormat.RGB_8,
               "Unexpected color formats of image layers");

        TextureArea area = packer_.allocateSpace(vec2us(cast(ushort)size.x, cast(ushort)size.y));
        if(area.valid)
        {
            diffuseTexture_.setPixels(area.min, diffuse);
            normalTexture_.setPixels(area.min, normal);
            offsetTexture_.setPixels(area.min, offset);
        }
        return area;
    }

    /// Remove a previously inserted image from the page.
    ///
    /// Params:  area = Texture area of the image to remove. Must be valid and
    ///                 previously returned by the insertImage() method of the
    ///                 same SpritePage instance.
    void removeImage(ref const TextureArea area) @safe pure nothrow
    {
        assert(area.valid, "Trying to remove an invalid texture area from a sprite page");
        packer_.freeSpace(area);
    }

    /// Get size of the sprite page in pixels.
    @property vec2u size() @safe const pure nothrow {return size_;}

    /// Is the sprite page empty (i.e. are no images in it)?
    @property bool empty() @safe const pure nothrow {return packer_.empty;}

    /// Get a string representation of the sprite page.
    string toString() @trusted const
    {
        return "GenericSpritePage!" ~ typeid(TexturePacker).toString() ~ 
               "{size_: " ~ to!string(size_) ~ 
               ", initialized_: " ~ to!string(initialized_) ~
               ", diffuseTexture_@" ~ to!string(diffuseTexture_) ~ ": " ~ 
               (diffuseTexture_ is null ? "N/A" : to!string(diffuseTexture_)) ~
               ", normalTexture_@" ~ to!string(normalTexture_) ~ ": " ~ 
               (normalTexture_ is null ? "N/A" : to!string(normalTexture_)) ~
               ", offsetTexture_@" ~ to!string(offsetTexture_) ~ ": " ~ 
               (offsetTexture_ is null ? "N/A" : to!string(offsetTexture_)) ~
               ", packer_: " ~ to!string(packer_) ~
               "}";
    }
}
/// Alias for a sprite page with the currently default texture packer.
alias GenericSpritePage!BinaryTexturePacker SpritePage;

/// Create a sprite page with specified size.
///
/// Params:  renderer = Renderer to create textures of the page.
///          size     = Size of the page to create in pixels.
///                     Must be power-of-two and no dimension can be
///                     greater than 65535 (effectively the maximum page size is 
///                     32768x32768).
///
/// Returns: Pointer to the new page on success (must be deleted by free() after use),
///          null on failure.
SpritePage* createSpritePage(Renderer renderer, const vec2u size)
{
    // We're using null return instead of exceptions for failures, 
    // so we're using goto instead of scope(failure) for cleanup.

    assert(size.x.isPot && size.y.isPot, "Trying to create a non-power-of-two sprite page");
    assert(size.x <= ushort.max && size.y <= ushort.max, 
           "Textures with X or Y size over 65535 are not supported");

    SpritePage* result = alloc!SpritePage;
    result.size_ = size;

    // Empty image data to init the textures.
    Image emptyRGBAImage   = Image(size.x, size.y, ColorFormat.RGBA_8);
    Image emptyRGBImage    = Image(size.x, size.y, ColorFormat.RGB_8);
    const textureParams    = TextureParams().filtering(TextureFiltering.Nearest);

    // Create the textures.
    result.diffuseTexture_ = renderer.createTexture(emptyRGBAImage, textureParams);
    if(result.diffuseTexture_ is null) {goto RESULT_CLEANUP;}
    result.normalTexture_  = renderer.createTexture(emptyRGBImage, textureParams);
    if(result.normalTexture_ is null)  {goto DIFFUSE_CLEANUP;}
    result.offsetTexture_  = renderer.createTexture(emptyRGBImage, textureParams);
    if(result.offsetTexture_ is null)  {goto NORMAL_CLEANUP;}

    result.packer_ = BinaryTexturePacker(vec2us(cast(ushort)size.x, cast(ushort)size.y));
    result.initialized_ = true;

    return result;

    // Cleanup after failures.
    NORMAL_CLEANUP:
    free(result.normalTexture_);
    DIFFUSE_CLEANUP:
    free(result.diffuseTexture_);
    RESULT_CLEANUP:
    free(result);
    return null;
}
