
//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// An OpenGL 2.0 backend using SDL 2.0 for OpenGL setup.
module video.sdl2glrenderer;


import std.stdio;
import std.string;

import derelict.opengl3.gl;
import derelict.sdl2.sdl;

import color;
import video.exceptions;
import video.glrenderer;


/// An OpenGL 2.0 backend using SDL 2.0 for OpenGL setup.
class SDL2GLRenderer : GLRenderer
{
private:
    /// Game window.
    SDL_Window* window_;
    /// GL context of the game.
    SDL_GLContext glContext_;

public:
    /// Construct an SDLGLRenderer.
    this()
    {
        writeln("Initializing SDLGLRenderer");
        super();
    }

    /// Destroy an SDLGLRenderer.
    ~this()
    {
        writeln("Destroying SDLGLRenderer");
        SDL_GL_DeleteContext(glContext_);  
        SDL_DestroyWindow(window_);
    }

    /// Set video mode.
    ///
    /// This must be called exactly once after construction.
    ///
    /// Params: width      = Video mode width in pixels.
    ///         height     = Video mode height in pixels.
    ///         format     = Video mode color format.
    ///                      Only RGB_565 and RGBA_8 are supported.
    ///         fullscreen = Use a fullscreen video mode?
    override void setVideoMode(const uint width, const uint height, 
                               const ColorFormat format, const bool fullscreen)
    {
        assert(!glInitialized_,
               "Trying to set video mode of an SDLGLVideoDriver more than once");
        assert(width >= 80 && width <= 65536, 
               "Can't set video mode with such ridiculous width");
        assert(height >= 60 && width <= 49152, 
               "Can't set video mode with such ridiculous height");

        // Determine bit depths of color channels.
        int red, green, blue, alpha, depth;
        depth = 24;
        switch(format)
        {
            case ColorFormat.RGB_565:
                red   = 5;
                green = 6;
                blue  = 5;
                alpha = 0;
                break;
            case ColorFormat.RGBA_8:
                red   = 8;
                green = 8;
                blue  = 8;
                alpha = 8;
                break;
            default:
                assert(false, "Unsupported video mode color format");
        }

        // Set up the internal GL screen pixel format.
        SDL_GL_SetAttribute(SDL_GL_RED_SIZE,     red);
        SDL_GL_SetAttribute(SDL_GL_GREEN_SIZE,   green);
        SDL_GL_SetAttribute(SDL_GL_BLUE_SIZE,    blue);
        SDL_GL_SetAttribute(SDL_GL_ALPHA_SIZE,   alpha);
        SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE,   depth);
        SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);

        auto flags = SDL_WINDOW_OPENGL/*TODO |SDL_WINDOW_RESIZABLE*/;
        if(fullscreen){flags |= SDL_WINDOW_FULLSCREEN;}
        // Create a window. Window mode MUST include SDL_WINDOW_OPENGL for use with OpenGL.
        window_ = SDL_CreateWindow
            ("Awesome2D Demo", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, 
             width, height, flags);
        assert(window_ !is null, "Failed to create window");

        glContext_ = SDL_GL_CreateContext(window_);
        assert(glContext_ !is null, "Failed to create GL context");

        // Print the GL screen pixel format.
        SDL_GL_GetAttribute(SDL_GL_RED_SIZE,   &red);
        SDL_GL_GetAttribute(SDL_GL_GREEN_SIZE, &green);
        SDL_GL_GetAttribute(SDL_GL_BLUE_SIZE,  &blue);
        SDL_GL_GetAttribute(SDL_GL_ALPHA_SIZE, &alpha);
        SDL_GL_GetAttribute(SDL_GL_DEPTH_SIZE, &depth);
        const uint bitDepth = red + green + blue + alpha;
        writefln("Red: %d, Green: %d, Blue: %d, Alpha: %d, Depth: %d\n",
                 red, green, blue, alpha, depth);

        screenWidth_  = width;
        screenHeight_ = height;
        screenDepth_  = bitDepth;
        initGL();
    }

    override void swapBuffers()
    {
        const error = glGetError();
        SDL_GL_SwapWindow(window_);
    }
}
