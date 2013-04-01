
//          Copyright Ferdinand Majerech 2012-2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


module gui.stylemanager;


import demo.spritemanager;
import gui.event;
import util.linalg;
/*import video.renderer;*/

/// Horizontal alignments.
enum AlignX
{
    /// Align to the left.
    Left,
    /// Align to center.
    Center,
    /// Align to the right.
    Right
}

/// Vertical alignments.
enum AlignY
{
    /// Align to top.
    Top,
    /// Align to center.
    Center,
    /// Align to bottom.
    Bottom
}

/// Base class for style managers.
///
/// A style manager manages styles of a widget (e.g. default, mouseOver, etc.).
///
/// Each StyleManager implementation implements its own drawing logic and
/// supports different kinds of styles.
abstract class StyleManager
{
protected:
    /// Sprite manager used to load sprites.
    SpritePlainManager spriteManager_;

public:
    /// Set style with specified name.
    ///
    /// Params: name = Name of style to set. If there is no style with specified 
    ///                name, the default style is set.
    ///                "default" is the name of the default style.
    void setStyle(string name) @safe pure;

    /// Draw the widget rectangle; both its background and border.
    ///
    /// Params: renderEvent = Render event that triggered this draw call.
    ///         maxBounds   = Minimum bounds of the area taken by the widget in screen space.
    ///         minBounds   = Maximum bounds of the area taken by the widget in screen space.
    void drawWidgetRectangle
        (ref RenderEvent renderEvent, const vec2i minBounds, const vec2i maxBounds) @trusted;

    /// Draw a progress "bar".
    ///
    /// Different styles might draw progress differently (horizontal or vertical
    /// bar, circle, cake, etc).
    ///
    /// Params: renderEvent = Render event that triggered this draw call.
    ///         progress    = Progress between 0 and 1.
    ///         maxBounds   = Minimum bounds of the area taken by the progress "bar".
    ///         minBounds   = Maximum bounds of the area taken by the progress "bar".
    void drawProgress(ref RenderEvent renderEvent, const float progress,
                      const vec2i minBounds, const vec2i maxBounds) @trusted;

    /// Draw text using the style.
    ///
    /// Only bounds of the widget are specified; the style decides font, alignment,
    /// and other parameters of the text.
    ///
    /// Params: renderEvent = Render event that triggered this draw call.
    ///         text  = Text to draw.
    ///         maxBounds   = Minimum bounds of the area taken by the widget.
    ///         minBounds   = Maximum bounds of the area taken by the widget.
    void drawText(ref RenderEvent renderEvent, const string text,
                  const vec2i minBounds, const vec2i maxBounds) @trusted;

package:
    // Set the sprite manager to load sprites with.
    @property void spriteManager(SpritePlainManager rhs) @safe pure nothrow 
    {
        spriteManager_ = rhs;
    }
}
