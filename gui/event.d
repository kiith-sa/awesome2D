
//          Copyright Ferdinand Majerech 2012 - 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Base class for all events.
module gui.event;


import gl3n.linalg;

import demo.spritemanager;
import demo.vectorrenderer;
import font.fontrenderer;
import gui.widget;
import platform.key;


/// Base class for all events.
///
/// Propagated recursively through the widget tree. Widgets can register handler 
/// functions to react to events (e.g. rendering, user input, layout resizing, etc.).
class Event 
{
public:
    /// Specifies whether the event is moving down (sinking) or up (bubbling) the widget tree.
    enum Status
    {
        /// The event is sinking into subwidgets.
        Sinking,
        /// The event is bubbling back to parent widgets.
        Bubbling
    }

    /// Return the parent widget the event sunk from when sinking.
    @property Widget sunkFrom() @safe pure nothrow
    {
        assert(status_ == Status.Sinking,
               "Trying to get the widget we sunk from when not sinking");
        return sunkFrom_;
    }

    /// Is the widget sinking or bubbling?
    @property Status status() @safe const pure nothrow {return status_;}

package:
    // Specifies whether the event is sinking down or bubbling up the widget tree.
    //
    // Only Widget can set this as it traverses its subwidgets passing an event.
    Status status_;

    // Widget that handled the event previously during sinking.
    //
    // Used to pass the parent widget for various events.
    Widget sunkFrom_;
}

/// Used when widgets need to be resized. Passed before ExpandEvent.
///
/// An example is when a RootWidget is connected to a SlotWidget - all widgets
/// in the RootWidget's subtree need to be resized.
class MinimizeEvent: Event
{
}

/// Used when widgets need to be resized. Passed after MinimizeEvent.
///
/// Handled when sinking, passing the parent widget for the children to expand into.
///
/// SeeAlso: MinimizeEvent
class ExpandEvent: Event
{
}

/// Used to draw the widgets.
class RenderEvent: Event
{
    /// Used to draw sprites used in GUI.
    SpritePlainRenderer spriteRenderer;
    /// Used to draw vector graphics used in GUI.
    VectorRenderer vectorRenderer;
    /// Used to draw text.
    FontRenderer fontRenderer;

    /// Start drawing with the vector renderer.
    ///
    /// Should be called instead of vectorRenderer.startDrawing();
    /// reduces drawing starts/stops.
    void startVectorDrawing() @safe
    {
        if(spriteRenderer.drawing) {spriteRenderer.stopDrawing();}
        if(!vectorRenderer.drawing){vectorRenderer.startDrawing();}
    }

    /// Start drawing with the sprite renderer.
    ///
    /// Should be called instead of spriteRenderer.startDrawing();
    /// reduces drawing starts/stops.
    void startSpriteDrawing() @safe
    {
        if(vectorRenderer.drawing) {vectorRenderer.stopDrawing();}
        if(!spriteRenderer.drawing){spriteRenderer.startDrawing();}
    }

    /// Start drawing text.
    ///
    /// Must be called before drawing text.
    void startTextDrawing() @safe
    {
        // Need to stop these as the font renderer will use its own 
        // sprite renderer.
        if(spriteRenderer.drawing){spriteRenderer.stopDrawing();}
        if(vectorRenderer.drawing){vectorRenderer.stopDrawing();}
    }
}

/// Low level mouse key event. Usually not handled by widgets directly.
class MouseKeyEvent: Event
{
    /// Key state (pressed, released).
    KeyState state;
    /// Mouse key affected.
    MouseKey key;
    /// Mouse position during the press/release.
    vec2u position;
}

/// Mouse movement event.
class MouseMoveEvent: Event
{
    /// Mouse position after the movement.
    vec2u position;
    /// Relative movement of the mouse.
    vec2i relative;
}

/// Low level keyboard key event. Usually not handled by widgets directly.
class KeyboardEvent: Event
{
    /// Key state (pressed, released).
    KeyState state;
    /// Key affected.
    Key key;
    /// Unicode value of the key.
    dchar unicode;
}
