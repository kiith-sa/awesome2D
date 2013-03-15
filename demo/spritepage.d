//          Copyright Ferdinand Majerech 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// A large 3-layer texture whose space is partitioned into smaller areas used to store sprites.
module demo.spritepage;


import std.conv;
import std.typecons;

import gl3n.aabb;
import gl3n.linalg;

import color;
import demo.spritevertex;
import demo.texturepacker;
import image;
import math.math;
import memory.memory;
import video.renderer;
import video.texture;
import video.indexbuffer;
import video.vertexbuffer;


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

package:
    // Vertex buffer storing vertices used to draw inserted images.
    //
    // Vertices are stored in quadruplets - 4 vertices of a quad.
    VertexBuffer!(SpriteVertex)* vertices_;
    // Index buffer storing indices used to draw inserted images.
    //
    // Indices are stored in sextuplets - 2 triangles of a quad.
    IndexBuffer* indices_;

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
            free(vertices_);
            free(indices_);
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
    /// Params:  diffuse           = Diffuse color layer of the image.
    ///          normal            = Normal layer of the image.
    ///          offset            = Offset layer of the image.
    ///          spriteBoundingBox = 3D bounding box of the sprite.
    ///
    /// Returns: Texture area the image takes up on the page,
    ///          and the index of the first index buffer element 
    ///          used to draw this image.
    ///          If the image could not be inserted, the area is invalid
    ///          (must be checked by TextureArea.valid).
    Tuple!(TextureArea, uint)
        insertImage(ref const Image diffuse, ref const Image normal, 
                    ref const Image offset, ref const AABB spriteBoundingBox)
    {
        const size = diffuse.size;
        assert(!vertices_.bound && !indices_.bound,
               "Inserting an image to a SpritePage while its buffers are bound");
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

        auto indexBufferOffset = addVertices(size, area, spriteBoundingBox);
        return tuple(area, indexBufferOffset);
    }

    /// Remove a previously inserted image from the page.
    ///
    /// Params:  area = Texture area of the image to remove. Must be valid and
    ///                 previously returned by the insertImage() method of the
    ///                 same SpritePage instance.
    ///          indexBufferOffset = Offset to the index buffer of the page
    ///                              where the first index used to draw the image
    ///                              can be found.
    void removeImage(ref const TextureArea area, uint indexBufferOffset)
        @safe pure nothrow
    {
        // POSSIBLE OPTIMIZATION (GPU memory):
        // Keep a buffer of removed indexBufferOffsets so we can reuse them
        // when a new image is inserted.
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

private:
    // Add vertices and indices to draw a newly inserted image.
    //
    // Params:  size              = Size of the image in pixels.
    //          area              = Texture area where the image was inserted.
    //                              Will be updated with the index of the first 
    //                              index of the sprite in indices_.
    //          spriteBoundingBox = 3D bounding box of the sprite.
    //
    // Returns:  Index of the first index buffer element used to draw 
    //           this image.
    uint addVertices(const vec2u size, ref TextureArea area, ref const AABB spriteBoundingBox)
    {
        if(vertices_.locked()){vertices_.unlock();}
        if(indices_.locked()){indices_.unlock();}

        // Using integer division to make sure we end up on a whole-pixel boundary
        // (avoids blurriness).
        // 2D vertex positions are identical for all facings.
        const vMin  = vec2(-(cast(int)size.x / 2), -(cast(int)size.y / 2));
        const vMax  = vMin + vec2(size);

        alias SpriteVertex V;
        const pageSize = this.size;
        // Texture coords depends on the facing's sprite page and texture area on the page.
        const tMin = vec2(cast(float)area.min.x / pageSize.x,
                          cast(float)area.min.y / pageSize.y);
        const tMax = vec2(cast(float)area.max.x / pageSize.x,
                          cast(float)area.max.y / pageSize.y);
        const baseIndex = cast(uint)vertices_.length;
        const bbox = &spriteBoundingBox;
        // 2 triangles forming a quad.
        vertices_.addVertex(V(vMin,                 tMin,                 bbox.min, bbox.max));
        vertices_.addVertex(V(vMax,                 tMax,                 bbox.min, bbox.max));
        vertices_.addVertex(V(vec2(vMin.x, vMax.y), vec2(tMin.x, tMax.y), bbox.min, bbox.max));
        vertices_.addVertex(V(vec2(vMax.x, vMin.y), vec2(tMax.x, tMin.y), bbox.min, bbox.max));

        const indexBufferOffset = cast(uint)indices_.length;

        indices_.addIndex(baseIndex);
        indices_.addIndex(baseIndex + 1);
        indices_.addIndex(baseIndex + 2);
        indices_.addIndex(baseIndex + 1);
        indices_.addIndex(baseIndex);
        indices_.addIndex(baseIndex + 3);

        vertices_.lock();
        indices_.lock();

        return indexBufferOffset;
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

    result.vertices_ =
        renderer.createVertexBuffer!SpriteVertex(PrimitiveType.Triangles);
    result.indices_  = renderer.createIndexBuffer();

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
