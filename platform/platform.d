
//          Copyright Ferdinand Majerech 2010 - 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


///Platform abstraction.
module platform.platform;


import gl3n.linalg;

public import platform.key;
import util.weaksingleton;
import util.signal;


///Exception thrown at platform related errors.
class PlatformException : Exception{this(string msg){super(msg);}} 

/**
 * Handles platform specific functionality like input/output.
 *
 *
 * Signal:
 *     public mixin Signal!(KeyState, Key, dchar) key
 *
 *     Emitted when a key is pressed. Passes the key, its state and unicode value.
 *
 * Signal:
 *     public mixin Signal!(KeyState, MouseKey, vec2u) mouseKey 
 *
 *     Emitted when a mouse button is pressed. Passes the key, its state and mouse position.
 *
 * Signal:
 *     public mixin Signal!(vec2u, vec2i) mouseMotion
 *
 *     Emitted when mouse is moved. Passes mouse position and position change. 
 */
abstract class Platform
{
    mixin WeakSingleton;
    protected:
        ///Array of bools for each key specifying if the key is currently pressed.
        bool[Key] keysPressed_;

    private:
        ///Continue to run?
        bool run_ = true;

    public:
        ///Emitted when a key is pressed. Passes the key, its state and unicode value.
        mixin Signal!(KeyState, Key, dchar) key;
        ///Emitted when a mouse button is pressed. Passes the key, its state and mouse position.
        mixin Signal!(KeyState, MouseKey, vec2u) mouseKey;
        ///Emitted when mouse is moved. Passes mouse position and position change.
        mixin Signal!(vec2u, vec2i) mouseMotion;

        /**
         * Construct Platform.
         *
         * Throws:  PlatformException on failure.
         */
        this(){singletonCtor();}

        ///Destroy the Platform.
        ~this()
        {
            import std.stdio;
            writeln("Destroying Platform");
            key.disconnectAll();
            mouseKey.disconnectAll();
            mouseMotion.disconnectAll();

            singletonDtor();
        }
        
        ///Collect input and determine if the game should continue to run.
        bool run() {return run_;}

        ///Quit the platform, i.e. the game.
        final void quit() pure {run_ = false;}

        ///Set window caption string to str.
        @property void windowCaption(const string str);

        ///Hide the mouse cursor.
        void hideCursor();

        ///Show the mouse cursor.
        void showCursor();

        ///Determine if specified key is pressed.
        final bool isKeyPressed(const Key key) const pure nothrow
        {
            return (null is (key in keysPressed_)) ? keysPressed_[key] : false;
        }
}
