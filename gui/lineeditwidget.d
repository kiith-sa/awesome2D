
//          Copyright Ferdinand Majerech 2012 - 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// One-line text editor widget.
module gui.lineeditwidget;


import std.algorithm;
import std.array;
import std.uni;

import gui.event;
import gui.widget;
import gui.widgetutils;
import platform.key;
import util.linalg;
import util.signal;
import util.yaml;
import video.renderer;

/// One-line text editor widget.
class LineEditWidget: Widget
{
private:
    /// Entered text.
    string text_;

    /// Maximum number of characters that can be entered.
    uint maxCharacters_;

    /// Determines whether an entered character should be added to the text.
    bool delegate(dchar) characterFilter_;

public:
    /// Emitted when the user presses Enter.
    mixin Signal!(string) textEntered;

    /// Load a LineEditWidget from YAML.
    ///
    /// Do not call directly.
    this(ref YAMLNode yaml) @safe
    {
        bool defaultFilter(dchar c)
        {
            return isGraphical(c);
        }
        characterFilter_ = &defaultFilter;
        maxCharacters_   = widgetInitPropertyOpt(yaml, "maxCharacters", 16);
        focusable_ = true;
        super(yaml);
    }

    override void render(ref RenderEvent renderEvent) @safe
    {
        super.render(renderEvent);
        styleManager_.drawText(renderEvent, text_ ~ '_', layout.minBounds, layout.maxBounds);
    }

    /// Get entered text.
    @property string text() @safe const pure nothrow {return text_;}

    /// Set the function to determine whether an entered character should be added to the text.
    @property void characterFilter(bool delegate(dchar) rhs) @safe pure nothrow 
    {
        characterFilter_ = rhs;
    }

    /// Set the maximum number of characters that can be entered.
    @property void maxCharacters(const uint chars) @safe pure nothrow 
    {
        maxCharacters_ = chars;
        text_ = text_[0 .. min(text_.length, chars)];
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

    override void keyPressed(const Key key, const dchar unicode) @trusted
    {
        if(key == Key.Return)
        {
            // Send the entered text and clear it.
            auto output = text_;
            text_ = "";
            textEntered.emit(output);
        }
        else if(key == Key.Backspace)
        {
            text_ = text_.empty ? text_ : text_[0 .. $ - 1];
        }
        else if(characterFilter_(unicode) && text_.length < maxCharacters_)
        {
            text_ ~= unicode;
        }
    }
}
