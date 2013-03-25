//          Copyright Ferdinand Majerech 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Sprite type used to draw fonts.
/// In the "demo" package to access package fields of Sprite. 
/// (This will be "sprite" package in future).
module demo.spritetypefont;


import core.stdc.string;
import std.array;
import std.exception;
import std.stdio;
import std.string;
import std.typecons;

import derelict.freetype.ft;
import dgamevfs._;

import color;
import image;
import demo.camera2d;
import demo.sprite;
import demo.spritepage;
import demo.spriterenderer;
import demo.spritetype;
import demo.texturepacker;
import memory.memory;
import util.linalg;
import video.glslshader;
import video.renderer;
import video.uniform;
import video.vertexbuffer;


/// Sprite renderer used to draw font glyph sprites.
///
/// These are drawn in plain 2D space.
class SpriteFontRenderer : SpriteUnlitRenderer 
{
    alias GenericSpritePage!(SpriteTypeFont, BinaryTexturePacker) SpritePage;

    // Sprite page whose textures, vertex and index buffer are currently bound.
    //
    // Only matters when drawing.
    SpritePage* boundSpritePage_ = null;

    // Diffuse color texture unit.
    Uniform!int diffuseSamplerUniform_;

public:
    /// Construct a SpriteFontRenderer.
    ///
    /// Params:  renderer = Renderer used for graphics functionality.
    ///          dataDir  = Data directory (must contain a "shaders" subdirectory
    ///                     to load shaders from).
    ///          camera   = Reference to the camera used for viewing.
    ///
    /// Throws:  SpriteRendererInitException on failure.
    this(Renderer renderer, VFSDir dataDir, Camera2D camera) @safe
    {
        super(renderer, dataDir, camera, "font");
    }

    /// Draw a sprite at specified 2D position.
    ///
    /// Must be called between calls to startDrawing() and stopDrawing().
    ///
    /// Params:  sprite   = Pointer to the sprite to draw.
    ///          position = Position of the bottom-left corner of the sprite
    ///                     in plain 2D space (pixels).
    void drawSprite(Sprite* sprite, vec2 position) @trusted
    {
        assert(drawing_,
               "SpriteFontRenderer.drawSprite() called without calling startDrawing()");
        assert(renderer_.blendMode == BlendMode.Alpha,
               "Non-alpha blend mode when drawing a font glyph sprite");
        // Get on a whole-pixel boundary to avoid blurriness.
        position.x = round(position.x);
        position.y = round(position.y);

        uploadUniforms(position);

        assert(sprite.facings_.length == 1,
               "SpriteFontRenderer trying to draw a font glyph sprite with multiple facings");
        Sprite.Facing* facing = &(sprite.facings_[0]);
        SpritePage* page = cast(SpritePage*)facing.spritePage;
        // Don't rebind a sprite page if we don't have to.
        if(boundSpritePage_ != page)
        {
            if(boundSpritePage_ !is null){boundSpritePage_.release();}
            page.bind();
            boundSpritePage_ = page;
        }

        const indexOffset = facing.indexBufferOffset;
        assert(indexOffset % 6 == 0, "Sprite indices don't form sextets");
        // Assuming a vertex quadruplet per image, added in same order
        // as the indices. See vertex/index adding code in sprite type 
        // structs.
        const minVertex = (indexOffset / 6) * 4;
        const maxVertex = minVertex + 3;

        renderer_.drawVertexBuffer(page.vertices_, page.indices_, spriteShader_,
                                   facing.indexBufferOffset, 6, minVertex, maxVertex);
    }

protected:
    override void stopDrawing_() @trusted
    {
        if(boundSpritePage_ !is null) {boundSpritePage_.release();}
        boundSpritePage_ = null;
    }

    override void resetUniforms() @safe pure nothrow
    {
        super.resetUniforms();
        diffuseSamplerUniform_.reset();
    }

    override void initializeUniforms()
    {
        super.initializeUniforms();
        diffuseSamplerUniform_ = Uniform!int(spriteShader_.getUniformHandle("texDiffuse"));
        diffuseSamplerUniform_.value  = SpriteTextureUnit.Diffuse;
    }

    override void uploadUniforms(const vec2 position) @trusted
    {
        super.uploadUniforms(position);
        diffuseSamplerUniform_.uploadIfNeeded(spriteShader_);
    }
}


/// SpriteType used for font glyphs.
///
/// Sprites of this type only have a single layer: grayscale color.
/// A sprite is loaded from a font.
struct SpriteTypeFont
{
package:
    /// Only one layer is used - grayscale color.
    enum layerCount = 1;
    enum ColorFormat[layerCount]       layerFormats = [ColorFormat.GRAY_8];
    enum SpriteTextureUnit[layerCount] textureUnits = [SpriteTextureUnit.Diffuse];

    /// Recommended X as well as Y size of a new sprite page at construction.
    enum recommendedSpritePageSize = 256;

    /// We load sprites from a font.
    alias FT_Face SpriteSource;

    /// Vertex type used to draw this sprite type.
    ///
    /// Stores just plain 2D position and texture coordinate.
    alias demo.spritetype.SpritePlainVertex SpriteVertex;
    /// Sprite renderer for this sprite type.
    ///
    /// Supports sprite drawing at 2D coordinates.
    alias SpriteFontRenderer SpriteRenderer;

    /// Implementation of GenericSpritePage.addVertices() for this sprite type.
    ///
    /// Adds 4 vertices to draw the sprite quad to passed vertex buffer,
    /// with data based on the sprite type.
    ///
    /// The caller handles buffer unlocking/locking and index buffer.
    static void addVertices(VertexBuffer!SpriteVertex* vertices, const vec2u pageSize,
                            const vec2u size, ref TextureArea area, const(Sprite)* sprite)
    {
        // The sprite is positioned based on its lower-left corner.
        alias SpriteVertex V;
        // Texture coords depends on the facing's sprite page and texture area on the page.
        const tMin = vec2(cast(float)area.min.x / pageSize.x,
                          cast(float)area.min.y / pageSize.y);
        const tMax = vec2(cast(float)area.max.x / pageSize.x,
                          cast(float)area.max.y / pageSize.y);
        const baseIndex = cast(uint)vertices.length;
        // 2 triangles forming a quad.
        vertices.addVertex(V(vec2(0.0f, 0.0f),   tMin));
        vertices.addVertex(V(vec2(size),         tMax));
        vertices.addVertex(V(vec2(0.0f, size.y), vec2(tMin.x, tMax.y)));
        vertices.addVertex(V(vec2(size.x, 0.0f), vec2(tMax.x, tMin.y)));
    }

    /// Loads font sprites.
    ///
    /// A font sprite is loaded directly from a font.
    struct SpriteLoader
    {
    private:
        // FreeType font face.
        FT_Face fontFace_;

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

    public:
        /// Create a sprite representing a glyph.
        ///
        /// Params:  name = String storing the UTF-32 character to get glyph for.
        ///
        /// Returns: Pointer to the sprite on success. null on failure.
        ///          If a glyph sprite with any name was successfully created once,
        ///          a glyph sprite with the same name will always be successfully
        ///          created (i.e. glyph sprite reloading always succeeds).
        Sprite* loadSprite(string name) @trusted
        {
            auto sprite = alloc!Sprite;
            try
            {
                scope(failure){free(sprite);}
                buildSprite(sprite, name);
                return sprite;
            }
            catch(SpriteInitException e)
            {
                // No glyph for whitespace is not an error.
                if(!strip(name).empty)
                {
                    writeln("Font glyph sprite initialization error: \"", name, "\" : ", e.msg);
                }
                return null;
            }
        }

        /// Initialize a font glyph sprite.
        ///
        /// Params:  sprite = Sprite to initialize.
        ///          name   = String storing the UTF-32 character to get glyph for.
        ///
        /// Throws:  SpriteInitException on a sprite construction error.
        ///
        /// See_Also: loadSprite()
        void buildSprite(Sprite* sprite, string name)
        {
            // Decode the UTF-32 character from the name string.
            dchar c = dchar.max;
            foreach(i, ch; name)
            {
                assert(i == 0, "Font sprite name with more than one UTF-32 character");
                c = ch;
            }
            assert(c != dchar.max, "Empty font sprite name");

            const freetypeIndex = FT_Get_Char_Index(fontFace_, c);

            // Load the glyph to fontFace_.glyph.
            const uint loadFlags =
                FT_LOAD_TARGET_(FT_Render_Mode.FT_RENDER_MODE_NORMAL) | FT_LOAD_NO_BITMAP;
            if(FT_Load_Glyph(fontFace_, freetypeIndex, loadFlags) != 0) 
            { 
                throw new SpriteInitException("Failed to load glyph " ~ name);
            }
            FT_GlyphSlot slot = fontFace_.glyph;
            // Convert fontFace_.glyph to image.
            if(FT_Render_Glyph(slot, FT_Render_Mode.FT_RENDER_MODE_NORMAL) == 0) 
            {
                FT_Bitmap bitmap = slot.bitmap;
                const size = vec2u(bitmap.width, bitmap.rows);

                if(size.x == 0 || size.y == 0)
                {
                    throw new SpriteInitException("Rendered a zero-sized glyph");
                }

                // Image to create sprite from.
                Image[1] spriteImage;
                spriteImage[0] = Image(size.x, size.y, ColorFormat.GRAY_8);

                // Copy freetype bitmap to our image.
                memcpy(spriteImage[0].dataUnsafe.ptr, bitmap.buffer, size.x * size.y);
                // Antialiasing makes the glyph appear darker so we make it brighter.
                spriteImage[0].gammaCorrect(1.2);
                spriteImage[0].flipVertical();
                sprite.name_ = name;
                sprite.size_ = spriteImage[0].size;

                auto facings = allocArray!(Sprite.Facing)(1);
                scope(failure)
                {
                    // The loading might fail half-way; free the loaded facings (facing, that is)
                    // in that case.
                    cleanupFacings_(facings);
                    free(facings);
                    facings = null;
                }

                auto areaPageOffset = fitImageToAPage_(spriteImage, sprite);
                with(facings[0])
                {
                    // We don't care about rotation of the facing either.
                    textureArea         = areaPageOffset[0];
                    spritePage          = areaPageOffset[1];
                    indexBufferOffset   = areaPageOffset[2];
                    assert(isValid, "Constructed an invalid glyph sprite facing " ~ name);
                    enforce(isValid,
                            new SpriteInitException("Invalid glyph sprite facing: " ~ name));
                }

                sprite.facings_ = facings;
            }
            else 
            {
                throw new SpriteInitException("Failed to render glyph " ~ name);
            }
        }

        /// Initialize a sprite object by building a dummy sprite. Used when sprite reloading fails.
        ///
        /// Note that for this sprite type, sprite reloading can never fail. Therefore, this
        /// should never be called.
        ///
        /// Params:  sprite = Sprite to initialize.
        ///          name   = Name of the sprite.
        void buildDummySprite(Sprite* sprite, string name)
        {
            assert(false, "Trying to build a dummy font glyph sprite, meaning font glyph"
                          " sprite reloading failed.\nFont glyph sprite reloading should"
                          " never fail.");
        }
    }
}
