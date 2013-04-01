
//          Copyright Ferdinand Majerech 2012 - 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Simple static label widget.
module gui.labelwidget;


import std.typecons;

import gui.event;
import gui.guisystem;
import gui.layout;
import gui.stylemanager;
import gui.widget;
import gui.widgetutils;
import util.yaml;
import video.renderer;


/// Simple label widget.
class LabelWidget: Widget
{
private:
    // Label text.
    string text_;

public:
    /// Load a LabelWidget from YAML.
    ///
    /// Do not call directly.
    this(ref YAMLNode yaml) @safe
    {
        text_ = widgetInitProperty!string(yaml, "text");
        focusable_ = false;
        super(yaml);
    }

    override void render(ref RenderEvent renderEvent) @safe
    {
        super.render(renderEvent);
        styleManager_.drawText(renderEvent, text_, layout_.minBounds, layout_.maxBounds);
    }

    /// Get label text.
    @property string text() @safe const pure nothrow {return text_;}

    /// Set label text.
    @property void text(string rhs) @safe pure nothrow {text_ = rhs;}
}
