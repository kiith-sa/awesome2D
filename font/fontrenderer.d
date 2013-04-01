
//          Copyright Ferdinand Majerech 2010 - 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Font manager/renderer and text drawing code.
module font.fontrenderer;


import core.stdc.string;

import std.algorithm;
import std.stdio;
import std.typecons;

import derelict.freetype.ft;
import derelict.util.loader;
import derelict.util.exception;

import dgamevfs._;

import color;
import containers.vector;
import demo.camera2d;
import demo.sprite;
import demo.spritemanager;
import demo.spritetypefont;
import font.font;
import math.math;
import memory.memory;
import util.linalg;
import video.renderer;


// Manages pen state when drawing a text line.
package align(4) struct TextLineRenderer
{
private:
    // Font we're drawing with.
    Font drawFont_;
    // Does this font use kerning?
    bool kerning_;
    // FreeType font face.
    FT_Face fontFace_;
    // Freetype index of the previously drawn glyph (0 at first glyph).
    uint previousIndex_;
    // Current x position of the pen.
    uint PenX;

public:
    // Get height of the font we're drawing.
    @property uint height() @safe nothrow const pure {return drawFont_.height;}

    // Start drawing a string.
    void start()
    {
        fontFace_      = drawFont_.fontFace;
        kerning_       = drawFont_.kerning && kerning_;
        previousIndex_ = PenX = 0;
    }

    // Determine if the glyph of a character is loaded.
    //
    // Params:  c = Character to check.
    //
    // Returns: True if the glyph is loaded, false otherwise.
    bool hasGlyph(const dchar c) @safe const nothrow {return drawFont_.hasGlyph(c);}

    // Load the glyph for a character.
    //
    // Will render the glyph and create a sprite for it.
    //
    // Params:  c = Character to load the glyph for.
    void loadGlyph(const dchar c){drawFont_.loadGlyph(c);}

    // Get glyph sprite and offset to draw a glyph at.
    //
    // Params:  c      = Character we're drawing.
    //          offset = Offset to draw the glyph at will be written here
    //                   (relative to the start of the string).
    //
    // Returns: Pointer to the texture of the glyph.
    Sprite* glyph(const dchar c, out vec2i offset)
    {
        auto glyph = drawFont_.getGlyph(c);
        const uint glyphIndex = glyph.freetypeIndex;

        // Adjust pen with kering information.
        if(kerning_ && previousIndex_ != 0 && glyphIndex != 0)
        {
            FT_Vector kerning;
            FT_Get_Kerning(fontFace_, previousIndex_, glyphIndex, 
                           FT_Kerning_Mode.FT_KERNING_DEFAULT, &kerning);
            PenX += kerning.x / 64;
        }

        offset.x       = PenX + glyph.offset.x;
        offset.y       = glyph.offset.y;
        previousIndex_ = glyphIndex;

        // Move pen to the next glyph.
        PenX += glyph.advance;
        return glyph.sprite;
    }
}

/// Renders text and manages all font resources.
///
/// At most one instance should exist at any moment.
class FontRenderer
{
private:
    // Renderer used to create textures to store glyphs on.
    Renderer renderer_;
    // FreeType library handle.
    FT_Library freetypeLib_;

    // Font data directory.
    VFSDir fontDir_;

    // All currently loaded fonts. fonts_[0] is the default font.
    Font[] fonts_;

    // As of DMD 2.058, can't use this due to an AA DMD bug
    //Vector!(ubyte)[string] fontFiles_; 

    // Buffers storing font file data indexed by file names.
    alias Tuple!(string, "name", ubyte[], "data") FontData;
    FontData[] fontFiles_;

    // Fallback font name.
    string defaultFontName_ = "DejaVuSans.ttf";
    // Fallback font size.
    uint defaultFontSize_ = 12;

    // Currently set font.
    Font currentFont_;
    // Currently set font name.
    string fontName_;
    // Currently set font size.
    uint fontSize_;

    // Default number of quickly accessible characters in fonts.
    // Glyphs up to this unicode index will be stored in a normal
    // instead of associative array, speeding up their retrieval.
    // 512 covers latin with most important extensions.
    uint fastGlyphs_ = 512;

    // Is kerning enabled?
    bool kerning_ = true;

    alias GenericSpriteManager!SpriteTypeFont SpriteManager;
    // Draws font glyph sprites.
    SpriteManager.SpriteRenderer fontSpriteRenderer_;

public:
    /// Construct the font renderer and load the default font.
    ///
    /// Params:  renderer   = Renderer to create textures to store font glyphs on.
    ///          gameDir    = Game data directory.
    ///          fontCamera = Camera used when drawing font glyph sprites.
    ///
    /// Throws:  FontException on failure.
    this(Renderer renderer, VFSDir gameDir, Camera2D fontCamera)
    {
        renderer_ = renderer;
        fontSpriteRenderer_ =
            SpriteManager.constructSpriteRenderer(renderer, gameDir, fontCamera);
        writeln("Initializing FontRenderer");
        scope(failure){writeln("FontRenderer initialization failed");}

        try{fontDir_ = gameDir.dir("fonts");}
        catch(VFSException e)
        {
            throw new Exception("Could not open font directory: " ~ e.msg);
        }

        try
        {
            // Sometimes FreeType is missing a function we don't use,
            // we don't want to crash in that case.
            Derelict_SetMissingSymbolCallback((a, b) => true);
            // Load the FreeType library.
            DerelictFT.load(); 
            Derelict_SetMissingSymbolCallback(null);
        }
        catch(SharedLibLoadException e)
        {
            throw new FontException("Could not load FreeType library: " ~ e.msg);
        }

        // Initialize FreeType.
        if(FT_Init_FreeType(&freetypeLib_) != 0 || freetypeLib_ is null)
        {
            throw new FontException("FreeType initialization error");
        }

        // Load default font.
        try
        {
            loadFontFile(defaultFontName_);
            fonts_ ~= new Font(renderer_, freetypeLib_, getFont(defaultFontName_),
                               defaultFontName_, defaultFontSize_, fastGlyphs_);
            currentFont_ = fonts_[$ - 1];
            fontName_    = defaultFontName_;
            fontSize_    = defaultFontSize_;
        }
        catch(VFSException e)
        {
            throw new FontException("Could not open file with default font: " ~ e.msg);
        }
        catch(FontException e)
        {
            throw new FontException("Could not load default font: " ~ e.msg);
        }
    }

    /// When replacing the renderer, this must be called before the renderer is destroyed.
    void prepareForRendererSwitch()
    {
        fontSpriteRenderer_.prepareForRendererSwitch();
        foreach(font; fonts_)
        {
            font.prepareForRendererSwitch();
        }
        renderer_ = null;
    }

    /// When replacing the renderer, this must be called to pass the new renderer.
    ///
    /// This will reload graphics data, which might take a while.
    void switchRenderer(Renderer newRenderer)
    {
        assert(renderer_ is null,
               "FontRenderer switchRenderer() called without prepareForRendererSwitch()");
        foreach(font; fonts_)
        {
            font.switchRenderer(newRenderer);
        }
        fontSpriteRenderer_.switchRenderer(newRenderer);
        renderer_ = newRenderer;
    }

    /// Destroy the FontRenderer, together with all loaded fonts.
    ~this()
    {
        writeln("Destroying FontRenderer");
        foreach(ref font; fonts_){destroy(font);}
        foreach(ref pair; fontFiles_){free(pair.data);}
        destroy(fonts_);
        destroy(fontSpriteRenderer_);
        destroy(fontFiles_);
        FT_Done_FreeType(freetypeLib_);
        DerelictFT.unload(); 
    }

    /// Set the font to use. Will load the font if not yet loaded. If the font could not
    /// be found, the default font is used.
    ///
    /// Params:  fontName  = Name of the font to set.
    ///          forceLoad = Force the font/font size combination to be loaded immediately
    ///                      if not yet loaded, instead of being loaded at first use.
    void font(string fontName, const bool forceLoad = false)
    {
        //if "default", use default font
        if(fontName == "default"){fontName = defaultFontName_;}
        fontName_ = fontName;
        if(forceLoad){loadFont();}
    }

    /// Set font size to use.
    ///
    /// Params:  size      = Font size to set.
    ///          forceLoad = Force the font/font size combination to be loaded immediately
    ///                      if not yet loaded, instead of being loaded at first use.
    void fontSize(uint size, const bool forceLoad = false)
    {
        fontSize_ = size;
        if(forceLoad){loadFont();}
    }

    /// Set color of the font.
    @property void fontColor(const Color color) @safe pure nothrow
    {
        fontSpriteRenderer_.fontColor = color;
    }

    /// Draw a text line.
    ///
    /// Params:  position = Position to draw the text at (left-bottom corner of the text).
    ///          text     = Text to draw.
    void drawText(const vec2i position, const string text)
    {
        scope(failure){writeln("Error drawing text: " ~ text);}
        loadFont();
        fontSpriteRenderer_.startDrawing();
        scope(exit){fontSpriteRenderer_.stopDrawing();}
        auto lineRenderer = TextLineRenderer(currentFont_, kerning_);
        lineRenderer.start();
        // Offset of the current character relative to position.
        vec2i offset;
        // Iterating over utf-32 chars (conversion is automatic).
        foreach(dchar c; text)
        {
            if(!lineRenderer.hasGlyph(c))
            {
                // Need to interrupt drawing to add the glyph to the texture used to draw it.
                fontSpriteRenderer_.stopDrawing();
                lineRenderer.loadGlyph(c);
                fontSpriteRenderer_.startDrawing();
            }
            auto sprite = lineRenderer.glyph(c, offset);
            // The glyph might not have a graphic representation in the font.
            if(sprite is null){continue;}
            fontSpriteRenderer_.drawSprite(sprite, vec2(position + offset));
        }
    }

    // Get size of text as it would be drawn in pixels with current font settings.
    //
    // Params:  text = Text to get size of.
    //
    // Returns: Size of the text in X and Y. Y might be slightly imprecise.
    vec2u textSize(const string text)
    {
        loadFont();
        // Y size could be determined more precisely by getting
        // minimum and maximum extents of the text.
        return vec2u(currentFont_.textWidth(text, kerning_), currentFont_.size);
    }

    /// Is kerning enabled?
    @property bool kerning() @safe nothrow const pure {return kerning_;}

private:
    // Might be replaced by more serious resource management.

    // Load font data from a file if it's not loaded yet. 
    //
    // Params:  name = Name of the font in the fonts/ directory.
    //
    // Throws:  VFSException if the font file name is invalid or it could not be opened.
    void loadFontFile(const string name)
    {
        scope(failure){writeln("Could not read from font file: " ~ name);}

        //already loaded
        foreach(ref pair; fontFiles_) if(pair.name == name)
        {
            return;
        }

        auto file = fontDir_.file(name);

        fontFiles_ ~= FontData(name, cast(ubyte[])null);
        fontFiles_[$ - 1].data = allocArray!ubyte(cast(size_t)file.bytes);
        scope(failure)
        {
            free(fontFiles_[$ - 1].data);
            fontFiles_.length = fontFiles_.length - 1;
        }
        file.input.read(cast(void[])fontFiles_[$ - 1].data);
    }

    // Try to set font according to fontName_ and fontSize_.
    //
    // Will load the font if needed, and if it can't load, will
    // try to fall back to default font with fontSize_. If that can't
    // be done either, will set the default font and font size loaded at startup.
    void loadFont()
    {
        // Font is already set.
        if(currentFont_.name == fontName_ && currentFont_.size == fontSize_)
        {
            return;
        }

        bool findFont(ref Font font)
        {
            return font.name == fontName_ && font.size == fontSize_;
        }
        auto found = find!findFont(fonts_);

        // Font is already loaded, set it.
        if(found.length > 0)
        {
            currentFont_ = found[0];
            return;
        }

        // Fallback scenario when the font could not be loaded.
        void fallback(const string error)
        {
            writeln("Failed to load font: ", fontName_);
            writeln(error);

            // If we already have default font name and can't load it,
            // try font 0 (default with default size).
            if(fontName_ == defaultFontName_)
            {
                currentFont_ = fonts_[0];
                return;
            }
            // Couldn't load the font, try default with our size.
            fontName_ = defaultFontName_;
            loadFont();
        }

        // Font is not loaded, try to load it.
        Font newFont;
        try
        {
            loadFontFile(fontName_);
            newFont = new Font(renderer_, freetypeLib_, getFont(fontName_),
                               fontName_, fontSize_, fastGlyphs_);
            // Font was succesfully loaded, set it.
            fonts_ ~= newFont;
            currentFont_ = fonts_[$ - 1];
        }
        catch(VFSException e){fallback("Font file could not be read: " ~ e.msg);}
        catch(FontException e){fallback("FreeType error: " ~ e.msg);}
    }

    // Get data of font with specified name.
    ubyte[] getFont(string name) @safe pure nothrow
    {
        foreach(ref pair; fontFiles_) if(name == pair.name)
        {
            return pair.data;
        }
        assert(false, "No font with name " ~ name);
    }
}
