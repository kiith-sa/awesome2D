//          Copyright Ferdinand Majerech 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// A large layered texture partitioned into smaller areas used to store sprites.
module demo.spritepage;


import std.conv;
import std.typecons;

import gl3n.aabb;
import gl3n.linalg;

import color;
import demo.sprite;
import demo.spritetype;
import demo.texturepacker;
import image;
import math.math;
import memory.memory;
import video.renderer;
import video.texture;
import video.indexbuffer;
import video.vertexbuffer;


/// A large layered texture partitioned into smaller areas used to store sprites.
///
/// Most sprites consist of relatively small, non-power-of-two images.
/// These are packed into a larger, power-of-two sized image in the sprite page.
/// The page is composed of one or more textures of same size - layers,
/// storing diferent data, e.g. diffuse color, normals and offsets.
/// This allows to draw many sprites without swapping textures,
/// greatly improving performance.
///
/// A sprite page supports adding and removing images. Adding might fail
/// if there is not enough space. In that case, a different sprite page
/// must be used.
///
/// To draw sprites stored on the page, it must be bound using the bind()
/// method.
///
/// The SpriteType type parameter determines layers used by the page.
///
/// The TexturePacker type parameter allows to easily replace texture packer algorithms
/// if needed.
package struct GenericSpritePage(SpriteType, TexturePacker)
    if(SpriteType.layerCount >= 1)
{
private:
    // Textures - layers of the page, storing data such as color, normals, etc.
    Texture*[SpriteType.layerCount] textureLayers_;
    // Size of the texture page in pixels.
    vec2u size_;
    // Set to true when createSpritePage succeeds.
    //
    // Used to avoid destructor cleaning up uninitialized members.
    bool initialized_ = false;
    // Are the page's textures/vbuffer/ibuffer bound for drawing?
    bool bound_ = false;
    // Handles packing of images to the page's texture space.
    TexturePacker packer_;

package:
    // Vertex buffer storing vertices used to draw inserted images.
    //
    // Vertices are stored in quadruplets - 4 vertices of a quad.
    VertexBuffer!(SpriteType.SpriteVertex)* vertices_;
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
            foreach(layer; textureLayers_) {free(layer);}
            free(vertices_);
            free(indices_);
        }
    }

    /// Bind the page's textures and vertex/index buffers for drawing.
    ///
    /// No other textures, vertex or index buffers can be bound until 
    /// the sprite page is released by calling release().
    ///
    /// If the page is already bound, this call will be ignored.
    void bind()
    {
        if(bound_){return;}
        foreach(l, layer; textureLayers_)
        {
            layer.bind(SpriteType.textureUnits[l]);
        }
        vertices_.bind();
        indices_.bind();
        bound_ = true;
    }

    /// Release a bound SpritePage to allow binding other textures/vbuffers/ibuffers.
    ///
    /// The page must be bound when this is called.
    void release()
    {
        assert(bound_, "Trying to release a sprite page that is not bound");
        vertices_.release();
        indices_.release();
        bound_ = false;
    }

    /// Insert an image (part of a sprite) into the page.
    ///
    /// All layers must have the same size, an their color formats must
    /// match the layerFormats property of the SpriteType.
    ///
    /// Params:  spriteLayers = Images storing  layers of the sprite.
    ///                         All layers must have the same size and
    ///                         their color formats must match the
    ///                         layerFormats property of the SpriteType.
    ///          sprite       = Sprite to which the image belongs.
    ///
    /// Returns: Texture area the image takes up on the page,
    ///          and the index of the first index buffer element 
    ///          used to draw this image.
    ///          If the image could not be inserted, the area is invalid
    ///          (must be checked by TextureArea.valid).
    Tuple!(TextureArea, uint)
        insertImage(ref const(Image[SpriteType.layerCount]) spriteLayers,
                    const (Sprite)* sprite)
    {
        const size = spriteLayers[0].size;
        foreach(l, ref layer; spriteLayers)
        {
            assert(layer.size == size, "Sizes of image layers do not match");
            assert(layer.format == SpriteType.layerFormats[l], 
                   "Color formats of image layers do not match the sprite type");
        }
        assert(!vertices_.bound && !indices_.bound,
               "Inserting an image to a SpritePage while its buffers are bound");

        TextureArea area = packer_.allocateSpace(vec2us(cast(ushort)size.x, cast(ushort)size.y));
        if(area.valid) foreach(l, ref layer; spriteLayers)
        {
            textureLayers_[l].setPixels(area.min, layer);
        }

        auto indexBufferOffset = addVertices(size, area, sprite);
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

private:
    // Add vertices and indices to draw a newly inserted image.
    //
    // Params:  size   = Size of the image in pixels.
    //          area   = Texture area where the image was inserted.
    //                   Will be updated with the index of the first 
    //                   index of the sprite in indices_.
    //          sprite = Sprite the image belongs to.
    //
    // Returns:  Index of the first index buffer element used to draw 
    //           this image.
    uint addVertices(const vec2u size, ref TextureArea area, const(Sprite)* sprite)
    {
        return SpriteType.addVertices(vertices_, indices_, this.size, size,
                                      area, sprite);
    }
}

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
GenericSpritePage!(SpriteType, TexturePacker)* 
createGenericSpritePage(SpriteType, TexturePacker)
                       (Renderer renderer, const vec2u size)
{
    // We're using null return instead of exceptions for failures, 
    // so we're using goto instead of scope(failure) for cleanup.

    assert(size.x.isPot && size.y.isPot, "Trying to create a non-power-of-two sprite page");
    assert(size.x <= ushort.max && size.y <= ushort.max, 
           "Textures with X or Y size over 65535 are not supported");

    auto result  = alloc!(GenericSpritePage!(SpriteType, TexturePacker));
    result.size_ = size;

    // POSSIBLE OPTIMIZATION: Make these static, and destroy them in a static dtor.
    // Empty image data to init the textures.
    Image[SpriteType.layerCount] emptyImages;
    foreach(i, ref image; emptyImages)
    {
        image = Image(size.x, size.y, SpriteType.layerFormats[i]);
    }
    const textureParams    = TextureParams().filtering(TextureFiltering.Nearest);

    result.textureLayers_[] = null;
    foreach(t, ref texture; result.textureLayers_)
    {
        texture = renderer.createTexture(emptyImages[t], textureParams);
    }

    result.vertices_ = renderer.createVertexBuffer!(SpriteType.SpriteVertex)
                                                   (PrimitiveType.Triangles);
    result.indices_  = renderer.createIndexBuffer();

    result.packer_ = BinaryTexturePacker(vec2us(cast(ushort)size.x, cast(ushort)size.y));
    result.initialized_ = true;

    return result;

    CLEANUP:
    foreach(texture; result.textureLayers_) if(texture !is null)
    {
        free(texture);
    }
    free(result);
    return null;
}
