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
import gl3n.linalg;

import demo.sprite;
import demo.spritepage;
import demo.texturepacker;
import formats.image;
import image;
import math.math;
import memory.memory;
import video.renderer;
import util.yaml;


/// Constructs and manages sprites.
class SpriteManager
{
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

    // Game data directory used to load sprites.
    VFSDir gameDir_;

public:
    /// Construct a SpriteManager.
    ///
    /// Params:  renderer = Renderer to create graphics data.
    ///          gameDir  = Game data directory to load sprites from.
    this(Renderer renderer, VFSDir gameDir) @trusted
    {
        renderer_ = renderer;
        gameDir_  = gameDir;
    }

    /// Load a sprite.
    ///
    /// Params:  gameDir  = Game data directory.
    ///          name     = Name of the subdirectory of the game data directory
    ///                     containing the sprite images and metadata file (sprite.yaml).
    ///
    /// Returns: Pointer to the sprite on success, null on failure.
    Sprite* loadSprite(string name)
    {
        try
        {
            auto spriteDir  = gameDir_.dir(name);
            auto spriteYAML = loadYAML(spriteDir.file("sprite.yaml"));
            auto sprite     = alloc!Sprite;
            scope(failure){free(sprite);}
            sprite.name_ = name;

            // Load sprite metadata.
            auto spriteMeta   = spriteYAML["sprite"];
            sprite.size_      = fromYAML!vec2u(spriteMeta["size"], "sprite size");
            const offsetScale =
                fromYAML!float(spriteMeta["offsetScale"], "sprite offset scale");
            auto posExtents     = spriteMeta["posExtents"];
            sprite.boundingBox_ = AABB(offsetScale * fromYAML!vec3(posExtents["min"]),
                                       offsetScale * fromYAML!vec3(posExtents["max"]));

            // Load data for each facing ("image") in the sprite.
            auto images = spriteYAML["images"];
            enforce(images.length > 0, new SpriteInitException("Sprite with no images"));

            sprite.facings_ = loadSpriteFacings(spriteDir, images, sprite);
            sprite.constructGraphicsBuffers(renderer_);
            sprite.manager_ = this;

            sprites_ ~= sprite;
            return sprite;
        }
        catch(VFSException e)
        {
            writeln("Filesystem error loading sprite \"", name, "\" : ", e.msg);
            return null;
        }
        catch(YAMLException e)
        {
            writeln("YAML error loading sprite \"", name, "\" : ", e.msg);
            return null;
        }
        catch(SpriteInitException e)
        {
            writeln("Sprite initialization error loading sprite \"", name, "\" : ", e.msg);
            return null;
        }
    }

    /// Destroy the SpriteManager. Will destroy (with a warning) any remaining sprites.
    ///
    /// Must be called before the used renderer is destroyed.
    ~this()
    {
        foreach(sprite; sprites_) if(sprite !is null)
        {
            writeln("WARNING: Undeleted sprite at SpriteManager destruction; ",
                    "deleting it now");
            free(sprite);
        }
        foreach(page; spritePages_) if(page !is null)
        {
            free(page);
        }
    }

    /// When replacing the renderer, this must be called before the renderer is destroyed.
    void prepareForRendererChange()
    {
        // Delete all textures and vertex buffers.
        assert(false, "TODO");
    }

    /// When replacing the renderer, this must be called to pass the new renderer.
    ///
    /// This will reload graphics data, which might take a while.
    void changeRenderer(Renderer newRenderer)
    {
        // Reload/rebuild textures/vertex buffers.
        assert(false, "TODO");
    }

package:
    // Called by a sprite when it's deleted.
    void spriteDeleted(Sprite* sprite)
    {
        // Note that the sprite has already removed itself from its sprite page.
        foreach(ref s; sprites_) if(s is sprite)
        {
            s = null;
            return;
        }
        assert(false,
               "Trying to delete a nonexistent sprite (double-delete?): " ~ to!string(sprite));
    }

private:
    // Allocate a new sprite page with at least specified size.
    //
    // Returns:  true on success (a new page has been added to spritePages_),
    //           false on failure (a page of at least minimumSize could not be allocated).
    bool allocatePage(const vec2u minimumSize)
    {
        auto pageSize = vec2u(max(2048, minimumSize.x.potCeil), 
                              max(2048, minimumSize.y.potCeil));
        while(pageSize.x >= minimumSize.x && pageSize.y >= minimumSize.y &&
              pageSize.x.isPot && pageSize.y.isPot)
        {
            auto newPage = createSpritePage(renderer_, pageSize);
            if(newPage !is null)
            {
                spritePages_ ~= newPage;
                return true;
            }
            pageSize = vec2u(pageSize.x / 2, pageSize.y / 2);
        }
        writeln("Failed to allocate a texture page at least " ~
                to!string(minimumSize) ~ " large");
        return false;
    }

    // Load all facings of a sprite based on YAML metadata.
    //
    // Used only during sprite construction.
    //
    // Params:  spriteDir   = Directory to load the facings from.
    //          facingsMeta = YAML sequence of metadata for each facing.
    //          sprite      = Sprite these facings will be used in (passed for debugging).
    //
    // Throws:  YAMLException on a YAML parsing error. SpriteInitException if a facing 
    //          fails to load or is invalid (e.g. size does not match the sprite).
    //
    // Returns: A manually allocated array of facings. Must be deleted after use by free().
    Sprite.Facing[] loadSpriteFacings
        (VFSDir spriteDir, ref YAMLNode facingsMeta, Sprite* sprite)
    {
        auto facings = allocArray!(Sprite.Facing)(facingsMeta.length);
        scope(failure)
        {
            // The loading might fail half-way; free everything that was
            // loaded in that case.
            foreach(ref facing; facings) if(facing.isValid)
            {
                facing.spritePage.removeImage(facing.textureArea);
            }
            free(facings);
            facings = null;
        }
        uint i = 0;
        // Every "image" in metadata refers to a facing with multiple layers.
        foreach(ref YAMLNode image; facingsMeta) with(facings[i])
        {
            // Need to convert from degrees to radians.
            zRotation = fromYAML!float(image["zRotation"], "Sprite image rotation")
                        * (PI / 180.0);
            auto layers = image["layers"];

            Image diffuseImage, normalImage, offsetImage;
            try
            {
                auto diffuseFile = spriteDir.file(layers["diffuse"].as!string);
                auto normalFile  = spriteDir.file(layers["normal"].as!string);
                auto offsetFile  = spriteDir.file(layers["offset"].as!string);
                readImage(diffuseImage, diffuseFile);
                readImage(normalImage,  normalFile);
                readImage(offsetImage,  offsetFile);
                diffuseImage.flipVertical();
                normalImage.flipVertical();
                offsetImage.flipVertical();
            }
            catch(VFSException e)
            {
                throw new SpriteInitException
                    ("Couldn't read a facing of sprite " ~ sprite.name ~ ": " ~ e.msg);
            }
            catch(ImageFileException e)
            {
                throw new SpriteInitException
                    ("Couldn't read a facing of sprite " ~ sprite.name ~ ": " ~ e.msg);
            }

            auto areaAndPage = fitImageToAPage(diffuseImage, normalImage, offsetImage, sprite);
            textureArea = areaAndPage[0];
            spritePage  = areaAndPage[1];

            enforce(isValid,
                    new SpriteInitException("Invalid image in sprite " ~ sprite.name));
            ++i;
        }
        return facings;
    }

    // Fit a multi-layered image (part of a sprite) to one of the sprite pages.
    //
    // All images passed must have the same size, which must match the sprite size.
    //
    // Params:  diffuse = Diffuse color layer.
    //          normal  = Normal layer.
    //          offset  = Offset layer.
    //          sprite  = Sprite this image belongs to, for debugging.
    //
    // Returns: A tuple of texture area allocated for the image and a pointer to the 
    //          sprite page it was allocated on.
    // 
    // Throws:  SpriteInitException if no sprite page could allocate the space and
    //          a new sprite page large enough to fit the image could not be allocated.
    Tuple!(TextureArea, SpritePage*) fitImageToAPage
        (ref const Image diffuse, ref const Image normal, ref const Image offset, 
         const(Sprite)* sprite)
    {
        TextureArea facingArea;
        size_t pageIndex = size_t.max;

        // Try to find a page to fit the new texture to.
        foreach(index, page; spritePages_) if(page !is null)
        {
            facingArea = page.insertImage(diffuse, normal, offset);
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
            facingArea =
                spritePages_.back.insertImage(diffuse, normal, offset);
            assert(facingArea.valid, "Couldn't insert a sprite facing into a newly "
                                     "created page large enough to insert it");
        }

        return tuple(facingArea, spritePages_[pageIndex]);
    }
}
