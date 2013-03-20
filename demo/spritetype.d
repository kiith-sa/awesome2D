//          Copyright Ferdinand Majerech 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/// Code specific for individual sprite types.
module demo.spritetype;


import std.algorithm;
import std.exception;
import std.stdio;
import std.typecons;

import gl3n.aabb;

import dgamevfs._;

import color;
import demo.sprite;
import demo.spritemanager;
import demo.spriterenderer;
alias demo.spriterenderer.Sprite3DRenderer Sprite3DRenderer;
import demo.texturepacker;
import formats.image;
import image;
import math.math;
import memory.memory;
import util.linalg;
import util.yaml;
import video.exceptions;
import video.indexbuffer;
import video.renderer;
import video.vertexbuffer;

public:

/// SpriteType for sprites supporting 3D lighting.
///
/// Sprites of this type have 3 layers; diffuse color, normal and offset
/// (position within sprite bounding box). Each sprite is loaded from a directory
/// with multiple image files and a metadata file ("sprite.yaml").
struct SpriteType3D
{
package:
    /// Number of texture layers used by this sprite type.
    enum layerCount = 3;
    /// Color formats of individual texture layers.
    enum ColorFormat[layerCount] layerFormats = 
        [ColorFormat.RGBA_8, ColorFormat.RGB_8, ColorFormat.RGB_8];
    /// Texture units (as well as interpretations) of individual texture layers.
    enum SpriteTextureUnit[layerCount] textureUnits = 
        [SpriteTextureUnit.Diffuse, SpriteTextureUnit.Normal, SpriteTextureUnit.Offset];

    /// Vertex type used to draw this sprite type.
    ///
    /// Stores sprite bounding box along with vertex-specific 2D position and texture
    /// coordinate.
    alias demo.spritetype.Sprite3DVertex SpriteVertex;

    /// SpriteRenderer used to draw sprites of this type.
    ///
    /// This SpriteRenderer implementation supports
    /// adding and removing lights, and rendering sprites at 3D positions.
    alias Sprite3DRenderer SpriteRenderer;

    /// Implementation of GenericSpritePage.addVertices() for this sprite type.
    ///
    /// Adds 4 vertices to draw the sprite quad to passed vertex buffer,
    /// with data based on the sprite type.
    ///
    /// The caller handles buffer unlocking/locking and index buffer.
    static void addVertices(VertexBuffer!SpriteVertex* vertices, const vec2u pageSize,
                            const vec2u size, ref TextureArea area, const(Sprite)* sprite)
    {
        // 2D vertex positions are common for all facings.
        // The sprite is centered around [0,0] (2D sprite position will be added to that 
        // on shader).
        // Using integer division to make sure we end up on a whole-pixel boundary
        // (avoids blurriness).
        const vMin  = vec2(-(cast(int)size.x / 2), -(cast(int)size.y / 2));
        const vMax  = vMin + vec2(size);

        alias SpriteVertex V;
        // Texture coords depends on the facing's sprite page and texture area on the page.
        const tMin = vec2(cast(float)area.min.x / pageSize.x,
                          cast(float)area.min.y / pageSize.y);
        const tMax = vec2(cast(float)area.max.x / pageSize.x,
                          cast(float)area.max.y / pageSize.y);
        const baseIndex = cast(uint)vertices.length;
        const bbox = sprite.boundingBox;
        // 2 triangles forming a quad.
        vertices.addVertex(V(vMin,                 tMin,                 bbox.min, bbox.max));
        vertices.addVertex(V(vMax,                 tMax,                 bbox.min, bbox.max));
        vertices.addVertex(V(vec2(vMin.x, vMax.y), vec2(tMin.x, tMax.y), bbox.min, bbox.max));
        vertices.addVertex(V(vec2(vMax.x, vMin.y), vec2(tMax.x, tMin.y), bbox.min, bbox.max));
    }

    /// Loads 3D lit sprites.
    ///
    /// Each sprite is stored as a subdirectory containing a "sprite.yaml" metadata file
    /// and images storing every layer of every facing of the sprite.
    struct SpriteLoader
    {
    private:
        // Game data directory to load sprites from.
        VFSDir gameDir_;

        // Calls SpriteManager method that cleans up a partially initialized facings array.
        //
        // Called when sprite loading fails while loading facings.
        void function(Sprite.Facing[] facings) cleanupFacings_;

        alias Tuple!(TextureArea, void*, uint) delegate 
              (ref const (Image[layerCount]) layerImages, const(Sprite)* sprite) 
              PageFitterDelegate;

        // Calls SpriteManager's fitImageToAPage() method.
        //
        // See_Also: GenericSpriteManager.fitImageToAPage()
        PageFitterDelegate fitImageToAPage_;

    package:
        /// Load a sprite.
        ///
        /// Params:  name = Name of the subdirectory of the game data directory
        ///                 containing the sprite images and metadata file (sprite.yaml).
        ///
        /// Returns: Pointer to the sprite on success, null on failure.
        Sprite* loadSprite(string name) @trusted
        {
            auto sprite = alloc!Sprite;
            try
            {
                scope(failure){free(sprite);}
                buildSprite(sprite, name);
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

        // Initialize a sprite object.
        //
        // Params:  sprite = Sprite to initialize.
        //          name   = Name of the sprite's subdirectory in the game directory.
        //
        // Throws:  SpriteInitException on a sprite construction error.
        //          YAMLException on a YAML parsing error.
        //          VFSException on a file system error.
        //
        // See_Also: loadSprite()
        void buildSprite(Sprite* sprite, string name)
        {
            auto spriteDir  = gameDir_.dir(name);
            auto spriteYAML = loadYAML(spriteDir.file("sprite.yaml"));
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
        }

        // Initialize a sprite object by building a dummy sprite. Used when sprite reloading fails.
        //
        // Params:  sprite = Sprite to initialize.
        //          name   = Name of the sprite.
        void buildDummySprite(Sprite* sprite, string name)
        {
            sprite.name_ = name;

            // Load sprite metadata.
            sprite.size_      = vec2u(64, 64);
            sprite.boundingBox_ = AABB(vec3(-100.0f, -100.0f, -100.0f),
                                       vec3( 100.0f,  100.0f,  100.0f));

            auto facings = allocArray!(Sprite.Facing)(1);
            try with(facings[0])
            {
                zRotation = 0.0f;
                Image[layerCount] layerImages;
                foreach(i, ref image; layerImages)
                {
                    image = Image(64, 64, layerFormats[i]);
                    image.generateCheckers(8);
                }

                auto areaPageOffset = fitImageToAPage_(layerImages, sprite);
                textureArea         = areaPageOffset[0];
                spritePage          = areaPageOffset[1];
                indexBufferOffset   = areaPageOffset[2];
                assert(isValid, "Constructed an invalid dummy sprite facing");
            }
            catch(SpriteInitException e)
            {
                auto msg = "Can't create a dummy sprite - out of texture memory? " ~ e.msg;
                debug{assert(false, msg);}
                else{throw new Error(msg);}
            }
        }

    private:
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
                cleanupFacings_(facings);
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

                Image[layerCount] layerImages;
                try foreach(i, layer; tuple("diffuse", "normal", "offset"))
                {
                    auto imageFile = spriteDir.file(layers[layer].as!string);
                    readImage(layerImages[i], imageFile);
                    layerImages[i].flipVertical();
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

                auto areaPageOffset = fitImageToAPage_(layerImages, sprite);
                textureArea         = areaPageOffset[0];
                spritePage          = areaPageOffset[1];
                indexBufferOffset   = areaPageOffset[2];
                assert(isValid, "Constructed an invalid 3D-lit sprite facing");

                enforce(isValid,
                        new SpriteInitException("Invalid image in sprite " ~ sprite.name));
                ++i;
            }
            return facings;
        }
    }
}

/// SpriteType for simple RGBA color sprites without multiple facings or lighting support.
///
/// Used e.g. by GUI.
///
/// Sprites of this type only have a single layer: RGBA color.
/// A sprite is loaded directly from an image file.
struct SpriteTypePlain
{
package:
    /// Just one layer is used - RGBA color.
    enum layerCount = 1;
    enum ColorFormat[layerCount]       layerFormats = [ColorFormat.RGBA_8];
    enum SpriteTextureUnit[layerCount] textureUnits = [SpriteTextureUnit.Diffuse];

    /// Vertex type used to draw this sprite type.
    ///
    /// Stores just plain 2D position and texture coordinate.
    alias demo.spritetype.SpritePlainVertex SpriteVertex;
    /// Sprite renderer for this sprite type.
    ///
    /// Supports sprite drawing at 2D coordinates.
    alias SpritePlainRenderer SpriteRenderer;

    /// Implementation of GenericSpritePage.addVertices() for this sprite type.
    static uint addVertices(VertexBuffer!SpriteVertex* vertices,
                            IndexBuffer* indices, const vec2u pageSize,
                            const vec2u size, ref TextureArea area,
                            const(Sprite)* sprite) 
    {
        //TODO

        // Vertex positions are relative to the bottom-left corner of the sprite.
        assert(false, "TODO");
    }

    /// Loads plain sprites.
    ///
    /// A plain sprite is loaded directly from an image file.
    struct SpriteLoader
    {
        //TODO
    }
}


package:

/// Vertex type used to draw sprites supporting 3D lighting.
struct Sprite3DVertex
{
    // 2D position of the vertex.
    //
    // The position is relative to the 2D center of the sprite.
    // The 2D center is computed on shader from 3D position of the sprite.
    vec2 position;
    // Texture coordinate of the vertex.
    vec2 texCoord;
    // Minimum 3D bounds of the sprite.
    vec3 minOffsetBounds;
    // Maximum 3D bounds of the sprite.
    vec3 maxOffsetBounds;

    // Padding to a 32 byte boundary.
    vec3 padding1;
    // Ditto.
    vec3 padding2;

    // Metadata for Renderer.
    mixin VertexAttributes!(vec2, AttributeInterpretation.Position,
                            vec2, AttributeInterpretation.TexCoord,
                            vec3, AttributeInterpretation.MinOffsetBounds,
                            vec3, AttributeInterpretation.MaxOffsetBounds,
                            vec3, AttributeInterpretation.Padding,
                            vec3, AttributeInterpretation.Padding);
}

/// Vertex type used to draw plain, unlit sprites.
struct SpritePlainVertex
{
    // 2D position of the vertex relative to the bottom-left corner of the sprite.
    //
    // The bottom left corner is specified by the user when drawing the sprite and
    // passed to the shader as uniform.
    vec2 position;
    // Texture coordinate of the vertex.
    vec2 texCoord;

    // Padding to a 32 byte boundary.
    vec4 padding1;

    // Metadata for Renderer.
    mixin VertexAttributes!(vec2, AttributeInterpretation.Position,
                            vec2, AttributeInterpretation.TexCoord,
                            vec4, AttributeInterpretation.Padding);
}

/// Enumerates texture units used by sprite layers.
///
/// Also used in SpriteTypes to determine the layers of the sprite.
enum SpriteTextureUnit 
{
    /// Diffuse color texture unit.
    Diffuse = 0,
    /// Normal texture unit.
    ///
    /// Normals are encoded to RGB colors by R representing the X component of 
    /// the normal, G representing Y and B representing Z. The lowest color value 
    /// maps to -1 for the vector component, the highest to +1.
    Normal = 1,
    /// Position offset texture unit.
    ///
    /// Colors of this texture represent positions within the sprite's
    /// bounding box. R is the X coordinate, G is Y, and B is Z. The
    /// minimum color value (0) maps to the minimum coordinate value
    /// in the bounding box, while the maximum (255 or 1.0) is the 
    /// maximum value.
    Offset = 2
}
