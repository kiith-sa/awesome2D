
//          Copyright Ferdinand Majerech 2012 - 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Simple clickable button widget.
module gui.buttonwidget;


import std.typecons;

import gui.event;
import gui.guisystem;
import gui.labelwidget;
import gui.layout;
import gui.stylemanager;
import gui.widget;
import gui.widgetutils;
import platform.key;
import util.linalg;
import util.signal;
import util.yaml;


/// Simple clickable button widget.
class ButtonWidget: LabelWidget
{
public:
    /// Emitted when this button is pressed.
    mixin Signal!() pressed;

    /// Load a ButtonWidget from YAML.
    ///
    /// Do not call directly.
    this(ref YAMLNode yaml) @safe
    {
        super(yaml);
        focusable_ = true;
        addEventHandler!MouseKeyEvent(&detectActive);
    }

protected:
    override void gotFocus() @safe pure
    {
        styleManager_.setStyle("focused");
    }

    override void lostFocus() @safe pure
    {
        styleManager_.setStyle("");
    }

    override void clicked(const vec2u position, const MouseKey key) @safe
    {
        if(key == MouseKey.Left)
        {
            pressed.emit();
        }
    }

private:
    /// Event handler that detects whether the button is active (mouse pressed above it).
    Flag!"DoneSinking" detectActive(MouseKeyEvent event) @safe pure
    {
        if(event.status == Event.Status.Sinking && 
           guiSystem_.focusedWidget is this)
        {
            if(event.state == KeyState.Pressed)
            {
                styleManager_.setStyle("active");
            }
            else if(event.state == KeyState.Released)
            {
                // Widget is focused - we test that above 
                // (if it wasn't focused, style would be 
                // already changed back to default in lostFocus())
                styleManager_.setStyle("focused");
            }
        }
        return No.DoneSinking;
    }
}
