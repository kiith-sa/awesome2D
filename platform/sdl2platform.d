
//          Copyright Ferdinand Majerech 2010 - 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

///SDL 2.0 platform implementation.
module platform.sdl2platform;


import std.conv;
import std.stdio;
import std.string;

import derelict.sdl2.sdl;
import derelict.util.exception;

import platform.key;
import platform.platform;
import util.linalg;
import util.string;


///Platform implementation based on SDL 2.0 .
class SDL2Platform : Platform
{
private:
    /// Window used by the game. Renderer calls the methods to initialize and destroy it.
    SDL_Window* window_;

public:
    /**
     * Construct an SDL2Platform. 
     *
     * Initializes SDL.
     *
     * Throws:  PlatformException on failure.
     */
    this()
    {
        writeln("Initializing SDLPlatform");
        scope(failure){writeln("SDLPlatform initialization failed");}

        super();

        try
        {
            DerelictSDL2.load();
        }
        catch(SharedLibLoadException e)
        {
            throw new PlatformException("SDL library not found: " ~ e.msg);
        }
        catch(SymbolLoadException e)
        {
            throw new PlatformException("Unsupported SDL version: " ~ e.msg);
        }

        if(SDL_Init(SDL_INIT_VIDEO) < 0)
        {
            DerelictSDL2.unload();
            throw new PlatformException("Could not initialize SDL: " 
                                        ~ to!string(SDL_GetError()));
        }
    }

    ~this()
    {
        assert(window_ is null,
               "Renderer didn't deinitialize window before SDL2Platform destruction");
        writeln("Destroying SDLPlatform");
        SDL_Quit();
        DerelictSDL2.unload();
    }

    override bool run()
    {
        SDL_Event event;

        while(SDL_PollEvent(&event)) switch(event.type)
        {
            case SDL_QUIT:
                quit();
                break;
            case SDL_KEYDOWN:
            case SDL_KEYUP:
                processKey(event.key);
                break;
            case SDL_MOUSEBUTTONDOWN:
            case SDL_MOUSEBUTTONUP:
                processMouseKey(event.button);
                break;
            case SDL_MOUSEMOTION:
                processMouseMotion(event.motion);
                break;
            default:
                break;
        }
        return super.run();
    }

    @property override void windowCaption(const string str)
    {
        assert(window_ !is null, 
               "Trying to set window caption without creating a window first " ~
               "(Initialize a Renderer)");
        SDL_SetWindowTitle(window_, toStringzNoAlloc(str));
    }

    override void hideCursor(){SDL_ShowCursor(0);}

    override void showCursor(){SDL_ShowCursor(1);}

    /// Create the game window.
    ///
    /// Params:  fullscreen = Should the window be fullscreen?
    ///          width      = Window width in pixels.
    ///          height     = Window height in pixels.
    void initWindow(const bool fullscreen, const uint width, const uint height)
    {
        auto flags = SDL_WINDOW_OPENGL/*TODO |SDL_WINDOW_RESIZABLE*/;
        if(fullscreen){flags |= SDL_WINDOW_FULLSCREEN;}
        // Create a window. Window mode MUST include SDL_WINDOW_OPENGL for use with OpenGL.
        window_ = SDL_CreateWindow
            ("Awesome2D Demo", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, 
             width, height, flags);
        assert(window_ !is null, "Failed to create window");
    }

    /// Destroy the game window.
    void destroyWindow()
    {
        SDL_DestroyWindow(window_);
        window_ = null;
    }

    /// Create a GL context and return a reference to it.
    ///
    /// createWindow() must be called first.
    SDL_GLContext createGLContext()
    {
        assert(window_ !is null,
               "Trying to create GL context without creating a window first!");
        return SDL_GL_CreateContext(window_);
    }

    /// Swaps the front and back buffer of the window.
    void swapWindow()
    {
        assert(window_ !is null, "No window to swap");
        SDL_GL_SwapWindow(window_);
    }

package:
    ///Process a keyboard event.
    void processKey(const SDL_KeyboardEvent event)
    {
        KeyState state = KeyState.Pressed;
        keysPressed_[cast(Key)event.keysym.sym] = true;
        if(event.type == SDL_KEYUP)
        {
            state = KeyState.Released;
            keysPressed_[cast(Key)event.keysym.sym] = false;
        }
        key.emit(state, cast(Key)event.keysym.sym, event.keysym.unicode);
    }

    ///Process a mouse button event.
    void processMouseKey(const SDL_MouseButtonEvent event) 
    {
        const state = event.type == SDL_MOUSEBUTTONUP ? KeyState.Released 
                                                      : KeyState.Pressed;

        //Convert SDL button to MouseKey enum.
        MouseKey key;
        switch(event.button)
        {
            case SDL_BUTTON_LEFT:   key = MouseKey.Left;   break;
            case SDL_BUTTON_MIDDLE: key = MouseKey.Middle; break;
            case SDL_BUTTON_RIGHT:  key = MouseKey.Right;  break;
            default: break;
        }

        const position = vec2u(event.x, event.y);

        mouseKey.emit(state, key, position);
    }

    ///Process a mouse motion event.
    void processMouseMotion(const SDL_MouseMotionEvent event) 
    {
        // Workaround around an SDL2 bug: 
        // the mouse position both absolute and relative, is not passed correctly in the event.
        static int x = int.max;
        static int y = int.max;
        const oldPos = vec2i(x, y);
        SDL_GetMouseState(&x, &y);
        //const position = vec2u(event.x, event.y);
        const positionRelative = oldPos.x != int.max ? vec2i(x, y) - oldPos : vec2i(0, 0);//vec2i(event.xrel, event.yrel);
        mouseMotion.emit(vec2u(x, y), positionRelative);
    }
}
