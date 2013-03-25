
//          Copyright Ferdinand Majerech 2010 - 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Font class.
module font.font;


import core.stdc.string;
import std.conv;
import std.stdio;

import derelict.freetype.ft;

import color;
import containers.vector;
import demo.sprite;
import demo.spritemanager;
import demo.spritetypefont;
import image;
import math.math;
import memory.memory;
import util.linalg;
import video.renderer;


/// Exception thrown at font related errors.
class FontException : Exception 
{
    public this(string msg, string file = __FILE__, int line = __LINE__) @safe pure nothrow
    {
        super(msg, file, line);
    }
}

/// Font glyph structure.
///
/// Contains information to draw the glyph as well as how to move the pen after it.
package struct Glyph
{
    /// Sprite used to draw the glyph.
    ///
    /// null if the glyph couldn't be rendered.
    Sprite* sprite;
    /// Freetype glyph index.
    uint freetypeIndex;
    /// Offset from the pen to the bottom-left corner of glyph image.
    vec2i offset;
    /// Pixels to advance the pen after drawing this glyph.
    short advance;
}
static assert(Glyph.sizeof <= 32);

/// Stores one font with one size (e.g. Inconsolata size 16 and 18 will be two Font objects).
package final class Font
{
private:
    // Default glyph to use when there is no glyph for a character.
    Glyph* defaultGlyph_ = null;
    // Number of fast glyphs.
    uint fastGlyphCount_;
    // Array storing fast glyphs. These are the first fastGlyphCount_ unicode indices.
    Glyph*[] fastGlyphs_;
    // Associative array storing other, "non-fast", glyphs.
    Glyph[dchar] glyphs_;

    // Name of the font (file name in the fonts/ directory) .
    string name_;
    // FreeType font face.
    FT_Face fontFace_;

    // Height of the font in pixels.
    uint height_;
    // Does this font support kerning?
    bool kerning_;

    alias GenericSpriteManager!SpriteTypeFont SpriteManager;

    // Loads sprites from a font.
    SpriteManager spriteManager_;

public:
    /// Construct a font.
    ///
    /// Params:  renderer     = Renderer to create textures to store glyphs on.
    ///          freetypeLib  = Handle to the freetype library used to work with fonts.
    ///          fontData     = Font data (loaded from a font file).
    ///          name         = Name of the font.
    ///          size         = Size of the font in points.
    ///          fastGlyphs   = Number of glyphs to store in fast access array,
    ///                         from glyph 0. E.g. 128 means 0-127, i.e. ASCII.
    ///
    /// Throws:  FontException if the font could not be loaded.
    this(Renderer renderer, FT_Library freetypeLib, ubyte[] fontData,
         const string name, const uint size, const uint fastGlyphs)
    {
        scope(failure){writeln("Could not load font " ~ name);}

        fastGlyphs_ = new Glyph*[fastGlyphs];
        fastGlyphCount_ = fastGlyphs;

        name_ = name;

        FT_Open_Args args;
        args.memory_base = fontData.ptr;
        args.memory_size = fontData.length;
        args.flags       = FT_OPEN_MEMORY;
        args.driver      = null;
        // We only support face 0 right now, so no bold, italic, etc in a single font file.
        // Unless it is in a separate font file.
        const face = 0;

        // Load face from memory buffer (fontData)
        if(FT_Open_Face(freetypeLib, &args, face, &fontFace_) != 0) 
        {
            throw new FontException("Couldn't load font face from font " ~ name);
        }

        // Set font size in pixels.
        // Could use a better approach, but worked for all fonts so far.
        if(FT_Set_Pixel_Sizes(fontFace_, 0, size) != 0)
        {
            throw new FontException("Couldn't set pixel size with font " ~ name);
        }

        spriteManager_  = new SpriteManager(renderer, fontFace_);

        height_ = size;
        kerning_ = cast(bool)FT_HAS_KERNING(fontFace_);
    }

    /// Destroy the font and free its resources.
    ~this()
    {
        foreach(glyph; fastGlyphs_) if(glyph !is null)
        {
            free(glyph);
        }
        FT_Done_Face(fontFace_);
        destroy(fastGlyphs_);
        destroy(glyphs_);
        destroy(spriteManager_);
    }

    /// Get size of the font in pixels.
    @property uint size() @safe const pure nothrow {return height_;}

    /// Get height of the font in pixels (currently the same as size).
    @property uint height() @safe nothrow const pure {return height_;}

    /// Get name of the font.
    @property string name() @safe nothrow const pure {return name_;}

    /// Does the font support kerning?
    @property bool kerning() @safe nothrow const pure {return kerning_;}

    /// Get FreeType font face of the font.
    @property FT_Face fontFace() @safe nothrow pure {return fontFace_;}

    /// When replacing the renderer, this must be called before the renderer is destroyed.
    void prepareForRendererSwitch()
    {
        spriteManager_.prepareForRendererSwitch();
    }

    /// When replacing the renderer, this must be called to pass the new renderer.
    ///
    /// This will reload graphics data, which might take a while.
    void switchRenderer(Renderer newRenderer)
    {
        spriteManager_.switchRenderer(newRenderer);
    }

package:
    /// Returns width of text as it would be drawn.
    ///
    /// Params:  str        = Text to measure.
    ///          useKerning = Should kerning be used?
    ///                       Can only be true if the font supports kerning.
    ///
    /// Returns: Width of the text in pixels.
    uint textWidth(const string str, const bool useKerning)
    in
    {
        assert(kerning_ ? true : !useKerning, 
               "Trying to use kerning with a font where it's unsupported.");
    }
    body
    {
        //previous glyph index, for kerning
        uint previousIndex = 0;
        uint penX = 0;
        //current glyph index
        uint glyphIndex;
        FT_Vector kerning;

        foreach(dchar chr; str) 
        {
            const glyph = getGlyph(chr);
            glyphIndex = glyph.freetypeIndex;

            if(useKerning && previousIndex != 0 && glyphIndex != 0) 
            {
                //adjust the pen for kerning
                FT_Get_Kerning(fontFace_, previousIndex, glyphIndex, 
                               FT_Kerning_Mode.FT_KERNING_DEFAULT, &kerning);
                penX += kerning.x / 64;
            }

            penX += glyph.advance;
        }
        return penX;
    }

    /// Access glyph of a (UTF-32) character.
    ///
    /// The glyph has to be loaded, otherwise a call to getGlyph()
    /// will result in undefined behavior.
    ///
    /// Params:  c = Character to get glyph for.
    ///
    /// Returns: Pointer to glyph corresponding to the character. 
    Glyph* getGlyph(const dchar c) @safe nothrow
    {
        //not asserting glyph existence here as it'd result in too much slowdown
        return c < fastGlyphCount_ ? fastGlyphs_[c] : c in glyphs_;
    }

    /// Determines if the glyph of a character is loaded.
    ///
    /// Params:  c = Character to check for.
    ///
    /// Returns: True if the glyph is loaded, false otherwise.
    bool hasGlyph(const dchar c) @safe const nothrow
    {
        return c < fastGlyphCount_ ? fastGlyphs_[c] !is null : (c in glyphs_) !is null;
    }

    /// Load glyph of a character. Must be called before getting the glyph.
    ///
    /// Params:  c = Character to load glyph for.
    void loadGlyph(const dchar c)
    {
        if(c < fastGlyphCount_)
        {
            if(fastGlyphs_[c] is null)
            {
                auto newGlyph = alloc!Glyph();
                scope(failure){free(newGlyph);}
                *newGlyph = renderGlyph(c);
                fastGlyphs_[c] = newGlyph;
                return;
            }
            *fastGlyphs_[c] = renderGlyph(c);
            return;
        }
        glyphs_[c] = renderGlyph(c);
    }

private:
    // Render a glyph for specified UTF-32 character and return it.
    //
    // If there is no glyph for the character, a glyph with a null sprite will
    // be returned. Such a glyph is still valid (e.g. a whitespace character might 
    // have no glyph but advance the pen forward).
    Glyph renderGlyph(const dchar c)
    {
        Glyph glyph;
        glyph.freetypeIndex = FT_Get_Char_Index(fontFace_, c);

        // Load the glyph to fontFace_.glyph.
        const uint loadFlags =
            FT_LOAD_TARGET_(FT_Render_Mode.FT_RENDER_MODE_NORMAL) | FT_LOAD_NO_BITMAP;
        if(FT_Load_Glyph(fontFace_, glyph.freetypeIndex, loadFlags) != 0) 
        {
            // Failed to load, create a dummy glyph.
            glyph.offset  = vec2i(0, cast(short)-height_);
            glyph.advance = cast(short)(height_ / 2);
            glyph.freetypeIndex = 0;
            glyph.sprite = null;
            return glyph;
        }
        FT_GlyphSlot slot = fontFace_.glyph;

        glyph.advance  = cast(short)(fontFace_.glyph.advance.x / 64);

        // POSSIBLE OPTIMIZATION:
        // We call Render_Glyph twice. Once here to get offset, and once in
        // SpriteTypeFont.SpriteLoader to create the glyph sprite. This could be
        // refactored.
        //
        // If the glyph fails to render (e.g. not in font), the offset will be zero
        // (by default).
        if(FT_Render_Glyph(slot, FT_Render_Mode.FT_RENDER_MODE_NORMAL) == 0) 
        {
            glyph.offset.x = cast(int)slot.bitmap_left;
            glyph.offset.y = cast(int)slot.bitmap_top - slot.bitmap.rows;
        }
        // Might return null, but a glyph with a null sprite is valid 
        // (it will just not be drawn).
        glyph.sprite = spriteManager_.loadSprite(to!string(""d ~ c));
        return glyph;
    }
}
