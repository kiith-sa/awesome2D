
//          Copyright Ferdinand Majerech 2012 - 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Base class for widget layoyts.
module gui.layout;


import gl3n.linalg;

import gui.widget;

/// Manages layout of a widget and its children.
/// 
/// When a widget is resized, its children need to be resized and repositioned 
/// accordingly. Implementations of Layout handle this in various ways.
abstract class Layout
{
protected:
    // Minimum extents of the widget.
    vec2i minBounds_;
    // Maximum extents of the widget.
    vec2i maxBounds_;

public:
    /// Minimize a widget's layout, determining its minimal bounds.
    ///
    /// minimize() is called for all widget layouts before expand().
    /// 
    /// Called for deepest children first, then for their parents, etc, until
    /// the root is reached. Children are already minimized when minimize() is 
    /// called.
    void minimize(Widget[] children) @safe;

    /// Expand a widget's layout, determining definitive sizes and positions of its children.
    /// 
    /// First called for root, then its children, etc; the parent 
    /// is already expanded when expand() is called.
    void expand(Widget parent) @safe;

    /// Get the minimum bounds of the layout in screen space.
    @property minBounds() @safe const pure nothrow {return minBounds_;}

    /// Get the maximum bounds of the layout in screen space.
    @property maxBounds() @safe const pure nothrow {return maxBounds_;}

protected:
    /// Allows layouts to access layouts of passed widgets.
    static Layout getLayout(Widget widget) @safe pure nothrow
    {
        return widget.layout;
    }
}
