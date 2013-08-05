
//          Copyright Ferdinand Majerech 2012 - 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Style manager that draws widgets as line rectangles.
module gui.linestylemanager;


import std.algorithm;
import std.array;
import std.conv;
import std.exception;

import color;
import demo.sprite;
import demo.spritemanager;
import demo.vectorrenderer;
import font.fontrenderer;
import gui.event;
import gui.exceptions;
import gui.stylemanager;
import gui.textbreaker;
import gui.widgetutils;
import memory.memory;
import util.linalg;
import util.yaml;


/// Style manager that draws widgets as line rectangles.
///
/// Widgets with this style manager have a colored (usually transparent) background, 
/// with a border made of lines. This is the most basic style manager - 
/// it's a placeholder before something more elaborate is implemented.
class LineStyleManager: StyleManager
{
public:
    /// LineStyleManager style.
    struct Style
    {
        /// Style of the progress "bar".
        enum ProgressStyle
        {
            Horizontal,
            Vertical
        }
        /// Name of the style. "default" for default style.
        string name           = "default";
        /// Font used to draw text.
        string font           = "default";
        /// Color of widget border.
        Color borderColor     = rgba!"FFFFFF60";
        /// Background color.
        Color backgroundColor = rgba!"00000000";
        /// Color of font used to draw text.
        Color fontColor       = rgba!"FFFFFF60";
        /// Color of the filled part of the progress bar.
        Color progressColor   = rgba!"8080FF80";
        /// Font size in points.
        uint fontSize         = 12;
        /// Gap between text lines in pixels.
        uint lineGap          = 2;
        /// Draw border of the widget?
        bool drawBorder       = true;
        /// Style of the progress "bar".
        ProgressStyle progressStyle;
        /// Filename of the background sprite (image), if any.
        string backgroundSpriteName = null;
        /// Background sprite, if any. Loaded when first drawn.
        Sprite* backgroundSprite    = null;
        /// Handles vector drawing functionality.
        StyleVectorData vectorData;
        /// X alignment of any text drawn in the widget.
        AlignX textAlignX = AlignX.Center;

        /// Construct a LineStyleManager style.
        ///
        /// Params: yaml = YAML to load the style from.
        ///         name = Name of the style.
        ///
        /// Throws: StyleInitException on error.
        this(ref YAMLNode yaml, string name) @safe
        {
            this.name       = name;
            drawBorder      = styleInitPropertyOpt(yaml, "drawBorder",      drawBorder);
            borderColor     = styleInitPropertyOpt(yaml, "borderColor",     borderColor);
            backgroundColor = styleInitPropertyOpt(yaml, "backgroundColor", backgroundColor);
            fontColor       = styleInitPropertyOpt(yaml, "fontColor",       fontColor);
            progressColor   = styleInitPropertyOpt(yaml, "progressColor",   progressColor);
            font            = styleInitPropertyOpt(yaml, "font",            font);
            fontSize        = styleInitPropertyOpt(yaml, "fontSize",        fontSize);
            lineGap         = styleInitPropertyOpt(yaml, "lineGap",         lineGap);

            auto textAlignXStr = styleInitPropertyOpt(yaml, "textAlignX", "center");
            switch(textAlignXStr)
            {
                case "right":  textAlignX = AlignX.Right;  break;
                case "left":   textAlignX = AlignX.Left;   break;
                case "center": textAlignX = AlignX.Center; break;
                default: 
                    throw new StyleInitException("Unsupported X alignment: " ~ textAlignXStr);
            }

            backgroundSpriteName =
                styleInitPropertyOpt(yaml, "backgroundImage", cast(string)null);
            const progressStyleString = 
                styleInitPropertyOpt(yaml, "progressStyle", "horizontal");
            enforce(["horizontal", "vertical"].canFind(progressStyleString),
                    new StyleInitException("Unknown progress style " ~ progressStyleString));
            switch(progressStyleString)
            {
                case "horizontal": progressStyle = ProgressStyle.Horizontal; break;
                case "vertical":   progressStyle = ProgressStyle.Vertical;   break;
                default: assert(false);
            }
        }

        @property bool hasBackgroundSprite() @safe const pure nothrow
        {
            return backgroundSpriteName !is null;
        }
    }

private:
    // Styles managed (e.g. default, mouse over, etc.)
    Style[] styles_;
    // Currently used style.
    Style style_;

public:
    /// Construct a LineStyleManager with specified styles.
    ///
    /// Styles must contain the default style (with name "default").
    this(ref Style[] styles) @safe pure
    in
    {
        foreach(i1, ref s1; styles) foreach(i2, ref s2; styles)
        {
            assert(i1 == i2 || s1.name != s2.name, 
                   "Two styles with identical names: \"" ~ s1.name ~ "\"");
        }
    }
    body
    {
        bool defStyle(ref Style s){return s.name == "default";}
        auto searchResult = styles.find!defStyle();
        assert(!searchResult.empty,
               "Trying to construct a LineStyleManager without a default style");
        style_  = searchResult.front;
        styles_ = styles;
    }

    override void setStyle(string name) @safe pure
    {
        bool matchingStyle(ref Style s){return s.name == name;}
        auto findResult = find!matchingStyle(styles_);
        if(findResult.empty)
        {
            bool defStyle(ref Style s){return s.name == "default";}
            style_ = styles_.find!defStyle().front;
            return;
        }
        style_ = findResult.front;
    }

    override void drawWidgetRectangle 
        (ref RenderEvent renderEvent, const vec2i minBounds, const vec2i maxBounds) @trusted
    {
        if(style_.hasBackgroundSprite) with(renderEvent)
        {
            renderEvent.startSpriteDrawing();
            if(style_.backgroundSprite is null)
            {
                style_.backgroundSprite =
                    spriteManager_.loadSprite(style_.backgroundSpriteName);
            }
            spriteRenderer.clipBounds(vec2(minBounds), vec2(maxBounds));
            spriteRenderer.drawSprite(style_.backgroundSprite, vec2(minBounds));
        }

        style_.vectorData.drawWidgetRectangle
            (style_, renderEvent, minBounds, maxBounds);
    }

    override void drawProgress
        (ref RenderEvent renderEvent, const float progress, 
         const vec2i minBounds, const vec2i maxBounds) @trusted
    {
        assert(progress >= 0.0f && progress <= 1.0f, "Progress out of range");

        style_.vectorData.drawProgress
            (style_, renderEvent, progress, minBounds, maxBounds);
    }

    override void drawText
        (ref RenderEvent renderEvent, const string text,
         const vec2i boundsMin, const vec2i boundsMax) @trusted
    {
        renderEvent.startTextDrawing();
        auto fontRenderer = renderEvent.fontRenderer;
        fontRenderer.font = style_.font;
        fontRenderer.fontSize = style_.fontSize;
        const textSize = fontRenderer.textSize(text);
        fontRenderer.fontColor = style_.fontColor;
        if(textSize.x > (boundsMax.x - boundsMin.x))
        {
            drawTextMultiLine(fontRenderer, text, boundsMin, boundsMax);
            return;
        }
        // At the moment, Y is always aligned to the center.
        int y = ((boundsMin.y + boundsMax.y) / 2) - textSize.y / 2;
        int x = xTextPosition(boundsMin, boundsMax, textSize.x);
        fontRenderer.drawText(vec2i(x, y), text);
    }

private:
    // Draw text wider than the widget, breaking it into multiple lines.
    // 
    // FontRenderer font and font size are expected to be set already.
    //
    // Params:  fontRenderer = FontRenderer to draw text with.
    //          text         = Text to draw.
    //          boundsMin    = Minimum bounds of the area taken up by the text.
    //          boundsMax    = Maximum bounds of the area taken up by the text.
    void drawTextMultiLine(FontRenderer fontRenderer, const string text,
                           const vec2i boundsMin, const vec2i boundsMax)
    {
        // Determines if passed text is plain ASCII.
        bool asciiText(const string text)
        {
            foreach(dchar c; text) if(cast(uint) c > 127)
            {
                return false;
            }
            return true;
        }

        // Draws passed text, breaking it into lines to fit into the widget area.
        //
        // One code unit is always one character in this function.
        void drawBrokenText(S)(S text)
        {
            vec2u textSizeWrap(S line)
            {
                return getTextSize(fontRenderer, line);
            }

            // Break the text into lines.
            static TextBreaker!S breaker;
            breaker.parse(text, cast(uint)(boundsMax.x - boundsMin.x), &textSizeWrap);
            if(breaker.lines.empty){return;}

            // Use the maximum line height of all lines in the text.
            uint lineGap = style_.lineGap;
            int lineHeight = 0;
            foreach(size; breaker.lineSizes) {lineHeight = max(lineHeight, size.y);}
            lineHeight += lineGap;

            int textHeight =
                cast(int)((lineHeight + lineGap) * breaker.lines.length - lineGap);

            // At the moment, Y is always aligned to the center.
            int y = ((boundsMin.y + boundsMax.y) / 2) - textHeight / 2;

            // Draw the lines.
            foreach(l, line; breaker.lines)
            {
                const width = breaker.lineSizes[l].x;
                const pos   = vec2i(xTextPosition(boundsMin, boundsMax, width), y);
                static if(is(T == string)) {fontRenderer.drawText(pos, line);}
                else                       {fontRenderer.drawText(pos, to!string(line));}
                y += lineHeight + lineGap;
            }
        }

        // Draw the text.
        if(!asciiText(text))
        {
            // To use slicing, we need one code point to be one character,
            // so convert to UTF-32 if we're not ASCII.
            auto text32 = to!dstring(text);
            drawBrokenText(text32);
            return;
        }
        drawBrokenText(text);
    }

    // Get the size of specified text when drawn on the screen.
    vec2u getTextSize(S)(FontRenderer fontRenderer, const S text)
    {
        // This could be cached based on text/font/fontSize combination
        fontRenderer.font     = style_.font;
        fontRenderer.fontSize = style_.fontSize;
        static if(is(S == string)) {return fontRenderer.textSize(text);}
        else                       {return fontRenderer.textSize(to!string(text));}
    }

    // Get X position of a text (using alignment).
    //
    // Params:  boundsMin = Minimum bounds of the area of the widget we're drawing text in.
    //          boundsMax = Minimum bounds of the area of the widget we're drawing text in.
    //          textWidth = Width of the text in pixels
    //
    // Returns: X position of the text (i.e. its left edge).
    int xTextPosition(const vec2i boundsMin, const vec2i boundsMax, const uint textWidth) 
        @safe pure nothrow
    {
        final switch(style_.textAlignX) with(AlignX)
        {
            case Left:   return boundsMin.x;
            case Center: return ((boundsMin.x + boundsMax.x) / 2)- textWidth / 2;
            case Right:  return boundsMax.x - textWidth;
        }
    }
}

private:

/// Stores vector graphics data used to draw widgets with a specific style.
///
/// Only used as a Style data member.
///
/// Caches the vector sprite - it is preserved between draws as each widget 
/// has a separate style manager instance, including a copy of all styles.
struct StyleVectorData
{
private:
    alias LineStyleManager.Style Style;
    // The vector sprite are deleted by the vector renderer after GUI is destroyed.

    // Vector sprite used to draw widget background and border.
    VectorSprite* widgetRectangle_ = null;
    // Vector sprite used to draw progressbar (if needed).
    VectorSprite* progressBar_ = null;
    // Widget size that was used to create the current widgetRectangle_.
    vec2i widgetSize_;
    // Progressbar size that was used to create the current progressBar_.
    vec2i progressSize_;
    // Progressbar progress that was used to create the current progressBar_.
    float progress_;

public:
    /// Draw widget rectangle; both its background and border.
    ///
    /// Params: style       = Style that owns this StyleVectorData. 
    ///         renderEvent = Render event that triggered this draw call.
    ///         maxBounds   = Minimum bounds of the area taken by the widget in screen space.
    ///         minBounds   = Maximum bounds of the area taken by the widget in screen space.
    void drawWidgetRectangle(ref Style style, ref RenderEvent renderEvent,
                             const vec2i minBounds, const vec2i maxBounds)
    {
        if(style.backgroundColor.a == 0 && !style.drawBorder) {return;}
        // If anything about the widget rectangle changes, regenerate it.
        if(widgetRectangle_ is null || maxBounds - minBounds != widgetSize_)
        {
            if(widgetRectangle_ !is null) {free(widgetRectangle_);}
            widgetRectangle_ = renderEvent.vectorRenderer.createVectorSprite();
            widgetSize_ = maxBounds - minBounds;
            // Background.
            auto color = style.backgroundColor;
            if(color.a > 0) with(*widgetRectangle_)
            {
                addTriangle(vec2(1, 1), color,
                            vec2(widgetSize_) - vec2(1,0), color,
                            vec2(1, widgetSize_.y), color);
                addTriangle(vec2(1, 1), color,
                            vec2(widgetSize_.x - 1, 1), color,
                            vec2(widgetSize_) - vec2(1, 0), color);
            }
            // Border.
            if(style.drawBorder) with(*widgetRectangle_)
            {
                color = style.borderColor;
                addLine(vec2(1, 0),                     color, vec2(widgetSize_.x, 0), color);
                addLine(vec2(widgetSize_.x, 0),         color, vec2(widgetSize_), color);
                addLine(vec2(widgetSize_) + vec2(1, 0), color, vec2(1, widgetSize_.y), color);
                addLine(vec2(0, widgetSize_.y + 1),     color, vec2(0, 0), color);
            }
            widgetRectangle_.lock();
        }
        with(renderEvent.vectorRenderer)
        {
            renderEvent.startVectorDrawing();
            drawVectorSprite(widgetRectangle_, vec3(minBounds.x, minBounds.y, 0.0f));
        }
    }

    /// Draw a progress "bar".
    ///
    /// Params: style       = Style that owns this StyleVectorData.
    ///         renderEvent = Render event that triggered this draw call.
    ///         progress    = Progress between 0 and 1.
    ///         maxBounds   = Minimum bounds of the area taken by the progress "bar".
    ///         minBounds   = Maximum bounds of the area taken by the progress "bar".
    void drawProgress(ref Style style, ref RenderEvent renderEvent,
                      const float progress, const vec2i minBounds, const vec2i maxBounds)
    {
        // If anything about the progress bar changes, regenerate it.
        if(progressBar_ is null || maxBounds - minBounds != progressSize_ || 
           progress != progress_)
        {
            if(progressBar_ !is null) {free(progressBar_);}
            progressBar_ = renderEvent.vectorRenderer.createVectorSprite();
            progressSize_ = maxBounds - minBounds - vec2i(1, 2);
            progress_     = progress;
            vec2 max;
            final switch(style.progressStyle) with(Style.ProgressStyle)
            {
                case Horizontal: max = vec2(progress * progressSize_.x, progressSize_.y);  break;
                case Vertical:   max = vec2(progressSize_.x, progress * progressSize_.y); break;
            }
            auto color = style.progressColor;
            progressBar_.addTriangle(vec2(0, 0), color,
                                     max, color,
                                     vec2(0, max.y), color);
            progressBar_.addTriangle(vec2(0, 0), color,
                                     vec2(max.x, 0), color,
                                     max, color);
            progressBar_.lock();
        }
        with(renderEvent.vectorRenderer)
        {
            renderEvent.startVectorDrawing();
            drawVectorSprite(progressBar_, vec3(vec2(minBounds) + vec2(0.0f, 1.0f), 0.0f));
        }
    }
}
