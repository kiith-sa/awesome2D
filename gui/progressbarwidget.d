
//          Copyright Ferdinand Majerech 2012-2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Simple progressbar widget.
module gui.progressbarwidget;


import std.stdio;
import std.typecons;

import gui.event;
import gui.guisystem;
import gui.layout;
import gui.stylemanager;
import gui.widget;
import gui.widgetutils;
import math.math;
import platform.key;
import util.signal;
import util.yaml;
import video.renderer;


/// Simple progressbar widget.
class ProgressBarWidget: Widget
{
private:
    // Current progress, between 0 and 1.
    float progress_;

public:
    /// Load a ProgressBarWidget from YAML.
    ///
    /// Do not call directly.
    this(ref YAMLNode yaml)
    {
        progress_ = widgetInitProperty!float(yaml, "progress");
        if(progress_ < 0.0f || progress > 1.0f)
        {
            writeln("WARNING: ProgressBar progress out of range - must be between 1 and 0.\n"
                    "Closest possible value will be used.");
        }
        progress_ = clamp(progress_, 0.0f, 1.0f);
        focusable_ = false;
        super(yaml);
    }

    override void render(ref RenderEvent renderEvent) @safe
    {
        styleManager_.drawProgress(renderEvent, progress_,
                                   layout_.minBounds, layout_.maxBounds);
        super.render(renderEvent);
    }

    /// Get current progress.
    @property float progress() @safe const pure nothrow {return progress_;}

    /// Set current progress.
    @property void progress(float rhs) @safe pure nothrow
    {
        assert(rhs >= 0.0f && rhs <= 1.0f, 
               "Trying to set progress outside of <0.0, 1.0>");
        progress_ = rhs;
    }
}
