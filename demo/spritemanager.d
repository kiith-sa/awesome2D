//          Copyright Ferdinand Majerech 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/// Constructs and manages sprites.
module demo.spritemanager;


import std.exception;
import std.stdio;
import std.typecons;

import dgamevfs._;
import gl3n.aabb;

import color;
import demo.camera2d;
import demo.sprite;
import demo.spritepage;
import demo.spriterenderer;
import demo.spritetype;
import demo.texturepacker;
import formats.image;
import image;
import math.math;
import memory.memory;
import util.linalg;
import util.yaml;
import video.renderer;

/// Constructs and manages sprites.
///
/// The sprite type (e.g. 3D lit or GUI sprites) is determined by the SpriteType parameter.
/// (See the spritetype module)
class GenericSpriteManager(SpriteType)
{
public:
    /// SpriteRenderer used to draw sprites managed by this manager.
    alias SpriteType.SpriteRenderer SpriteRenderer;

    /// Sprite page type used to pack sprites created by this manager.
    alias GenericSpritePage!(SpriteType, BinaryTexturePacker) SpritePage;

private:
    import containers.vector;
    alias containers.vector.Vector Vector;
    // Sprites constructed by this SpriteManager.
    //
    // Might contain null pointers, left behind deleted sprites.
    Vector!(Sprite*) sprites_;

    // Sprite pages storing image data of the sprites.
    //
    // Might contain null pointers, left behind deleted sprites.
    Vector!(SpritePage*) spritePages_;

    // Currently used renderer. Used to build textures and vertex buffers.
    Renderer renderer_;

    // Handles loading of sprites of specified SpriteType.
    SpriteType.SpriteLoader spriteLoader_;

public:
    /// Construct a SpriteManager.
    ///
    /// Params:  renderer     = Renderer to create graphics data.
    ///          spriteSource = Serves as the source to load sprites from.
    ///                         E.g. game data directory for sprites loaded from files,
    ///                         font for sprites loaded from a font.
    this(Renderer renderer, SpriteType.SpriteSource spriteSource) @trusted
    {
        renderer_     = renderer;
        spriteLoader_ =
            SpriteType.SpriteLoader(spriteSource, &cleanupFacings, &fitImageToAPage);
    }

    /// Construct a SpriteRenderer capable of rendering sprites created by this SpriteManager.
    ///
    /// Params:  renderer = Renderer to handle graphics operations.
    ///          dataDir  = Game data directory (to load shaders).
    ///          camera   = 2D camera used to view the scene.
    static SpriteRenderer constructSpriteRenderer
        (Renderer renderer, VFSDir dataDir, Camera2D camera) @safe
    {
        return new SpriteRenderer(renderer, dataDir, camera);
    }

    /// Load a sprite.
    ///
    /// If a sprite with specified name is already loaded, a pointer to it 
    /// will be returned instead of loading the same sprite again.
    ///
    /// Note: The meaning of this method depends on the SpriteType parameter.
    /// 
    /// For 3D lit sprites, name refers to the subdirectory containing the 
    ///     sprite metadata file and sprite images.
    /// For plain (1-facing, RGBA-only) sprites, name refers to the filename
    ///     of the image file to load sprite from.
    ///
    /// Only a SpriteRenderer created by this SpriteManager's createSpriteRenderer()
    /// method can be used to draw the created sprite.
    ///
    /// Returns: Pointer to the sprite on success, null on failure.
    Sprite* loadSprite(string name) @safe
    {
        foreach(sprite; sprites_) if(sprite.name == name)
        {
            return sprite;
        }
        Sprite* result = spriteLoader_.loadSprite(name);
        if(result !is null)
        {
            // SpriteLoader can't do this as it can't have a reference to SpriteManager
            // (recursive templates).
            result.onDestruction_ = &spriteDeleted;
            sprites_ ~= result;
        }
        return result;
    }

    /// Destroy the SpriteManager. Will destroy any remaining sprites
    /// created by this manager.
    ///
    /// Must be called before the used renderer is destroyed.
    ~this()
    {
        foreach(sprite; sprites_) if(sprite !is null)
        {
            free(sprite);
        }
        foreach(page; spritePages_) if(page !is null)
        {
            free(page);
        }
    }

    /// When replacing the renderer, this must be called before the renderer is destroyed.
    void prepareForRendererSwitch()
    {
        // Remove all sprites' images from sprite pages and delete
        // vertex/index buffers.
        foreach(sprite; sprites_) if(sprite !is null)
        {
            foreach(ref facing; sprite.facings_)
            {
                (cast(SpritePage*)facing.spritePage)
                    .removeImage(facing.textureArea, facing.indexBufferOffset);
            }
            free(sprite.facings_);
        }
        foreach(page; spritePages_) if(page !is null)
        {
            assert(page.empty, "Sprite page not empty after all sprites have been removed");
            free(page);
        }
        spritePages_.length = 0;
        renderer_ = null;
    }

    /// When replacing the renderer, this must be called to pass the new renderer.
    ///
    /// This will reload graphics data, which might take a while.
    void switchRenderer(Renderer newRenderer)
    {
        assert(renderer_ is null,
               "switchRenderer() called without prepareForRendererSwitch()");
        renderer_ = newRenderer;
        // Reload/rebuild textures/vertex buffers.
        foreach(sprite; sprites_) if(sprite !is null)
        {
            // Reloading might fail, but we can't afford to destroy a sprite 
            // the user might have another pointer to, so we just rebuild it
            // with dummy data in that case.
            try                          {spriteLoader_.buildSprite(sprite, sprite.name);}
            catch(SpriteInitException e) {spriteLoader_.buildDummySprite(sprite, sprite.name);}
            catch(YAMLException e)       {spriteLoader_.buildDummySprite(sprite, sprite.name);}
            catch(VFSException e)        {spriteLoader_.buildDummySprite(sprite, sprite.name);}
        }
    }

package:
    // Called by a sprite when it's deleted.
    void spriteDeleted(Sprite* sprite)
    {
        foreach(ref s; sprites_) if(s is sprite)
        {
            // Remove the facings from their sprite pages.
            foreach(ref facing; s.facings_)
            {
                assert(facing.isValid, "Invalid sprite facing at destruction");
                (cast(SpritePage*)(facing.spritePage))
                    .removeImage(facing.textureArea, facing.indexBufferOffset);
            }
            free(s.facings_);
            s = null;
            return;
        }
        assert(false,
               "Trying to delete a nonexistent sprite (double-delete?): " ~ to!string(sprite));
    }

    // Fit a multi-layered image (belonging to a sprite) to one of the sprite pages.
    //
    // Params:  layerImages = Image structs storing the layers of the image.
    //                        Must be in color formats matching the sprite 
    //                        type's layerFormats property. All images must have 
    //                        the same size, matching the sprite size.
    //          sprite      = Sprite this image belongs to, for debugging.
    //
    // Returns: A tuple of texture area allocated for the image, a (void*) pointer to the
    //          sprite page it was allocated on and the offset to the first index
    //          used to draw the image in the page's index buffer.
    // 
    // Throws:  SpriteInitException if no sprite page could allocate the space and
    //          a new sprite page large enough to fit the image could not be allocated.
    Tuple!(TextureArea, void*, uint) fitImageToAPage
        (ref const (Image[SpriteType.layerCount]) layerImages, const(Sprite)* sprite)
    {
        TextureArea facingArea;
        uint indexBufferOffset;
        size_t pageIndex = size_t.max;

        // Try to find a page to fit the new texture to.
        foreach(index, page; spritePages_) if(page !is null)
        {
            auto areaAndOffset = page.insertImage(layerImages, sprite);
            facingArea = areaAndOffset[0];
            indexBufferOffset = areaAndOffset[1];
            if(facingArea.valid) 
            {
                pageIndex = index;
                break;
            }
        }
        if(!facingArea.valid)
        {
            enforce(allocatePage(sprite.size),
                    new SpriteInitException(format("Failed to allocate a page area for "
                                                   "sprite %s with size %s", 
                                                   sprite.name, sprite.size)));
            pageIndex  = spritePages_.length - 1;
            auto areaAndOffset =
                spritePages_.back.insertImage(layerImages, sprite);
            facingArea = areaAndOffset[0];
            indexBufferOffset = areaAndOffset[1];
            assert(facingArea.valid, "Couldn't insert a sprite facing into a newly "
                                     "created page large enough to insert it");
        }

        return tuple(facingArea, cast(void*)(spritePages_[pageIndex]), indexBufferOffset);
    }

private:
    // Allocate a new sprite page with at least specified size.
    //
    // Returns:  true on success (a new page has been added to spritePages_),
    //           false on failure (a page of at least minimumSize could not be allocated).
    bool allocatePage(const vec2u minimumSize)
    {
        auto pageSize = vec2u(max(SpriteType.recommendedSpritePageSize, minimumSize.x.potCeil), 
                              max(SpriteType.recommendedSpritePageSize, minimumSize.y.potCeil));
        while(pageSize.x >= minimumSize.x && pageSize.y >= minimumSize.y &&
              pageSize.x.isPot && pageSize.y.isPot)
        {
            auto newPage = createGenericSpritePage!(SpriteType, BinaryTexturePacker)
                                                   (renderer_, pageSize);
            if(newPage !is null)
            {
                spritePages_ ~= newPage;
                return true;
            }
            pageSize = vec2u(pageSize.x / 2, pageSize.y / 2);
        }
        writeln("Failed to allocate a texture page at least ", minimumSize, " large");
        return false;
    }

    // Destroys any initialized facings in a partially initialized facings array.
    //
    // Used to clean up when sprite loading fails.
    // (Passed to SpriteLoader as a function pointer to avoid recursive templates).
    static void cleanupFacings(Sprite.Facing[] facings)
    {
        foreach(ref facing; facings) if(facing.isValid)
        {
            (cast(SpritePage*)(facing.spritePage))
                .removeImage(facing.textureArea, facing.indexBufferOffset);
        }
    }
}

alias GenericSpriteManager!SpriteType3D Sprite3DManager;
alias Sprite3DManager.SpriteRenderer Sprite3DRenderer;
alias GenericSpriteManager!SpriteTypePlain SpritePlainManager;
alias SpritePlainManager.SpriteRenderer SpritePlainRenderer;
