
//          Copyright Ferdinand Majerech 2012 - 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Fixed layout that never changes.
module gui.fixedlayout;


import gui.layout;
import gui.widget;
import gui.widgetutils;
import util.linalg;
import util.yaml;


/// Fixed layout - bounds of the widget are set from the start and don't change.
///
/// Useful for e.g. the root widget.
class FixedLayout: Layout
{
public:
    /// Construct a FixedLayout from YAML.
    this(ref YAMLNode yaml) @safe
    {
        minBounds_ = vec2i(layoutInitProperty!int(yaml, "x"),
                           layoutInitProperty!int(yaml, "y"));
        maxBounds_ = minBounds_ +
                     vec2i(layoutInitProperty!int(yaml, "w"),
                           layoutInitProperty!int(yaml, "h"));
    }

    override void minimize(Widget[] children) @safe pure nothrow {};
    override void expand(Widget parent) @safe pure nothrow {};

package:
    /// Manually set bounds of the layout.
    ///
    /// This is used _only_ by GUISystem for layout of the root widget.
    ///
    /// Params: min = Minimum extents of the bounds.
    ///         max = Maximum extents of the bounds. Both coordinates must be
    ///               greater or equal to those in min.
    void setBounds(const vec2i min, const vec2i max) @safe pure nothrow
    {
        assert(min.x <= max.x && min.y <= max.y, "Invalid layout bounds");
        minBounds_ = min;
        maxBounds_ = max;
    }
}
