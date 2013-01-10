
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
import platform.platform;
import platform.sdl2platform;
import video.exceptions;
import video.glrenderer;


/// An OpenGL 2.0 backend using SDL 2.0 for OpenGL setup.
class SDL2GLRenderer : GLRenderer
{
private:
    /// GL context of the game.
    SDL_GLContext glContext_;
    /// Reference to platform, used to e.g. create/destroy the window.
    SDL2Platform platform_;

public:
    /// Construct an SDLGLRenderer.
    ///
    /// Params:  platform = Platform handling window management. Must be an SDL2Platform.
    this(Platform platform)
    {
        writeln("Initializing SDLGLRenderer");
        platform_ = cast(SDL2Platform)platform;
        assert(platform_ !is null, "Non-SDL2 platform used with SDL2GLRenderer");
        super();
    }

    /// Destroy an SDLGLRenderer.
    ~this()
    {
        writeln("Destroying SDLGLRenderer");
        SDL_GL_DeleteContext(glContext_);
        platform_.destroyWindow();
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
        assert(width <= 65536, "Can't set video mode with such ridiculous width");
        assert(height <= 49152, "Can't set video mode with such ridiculous height");

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

        platform_.initWindow(fullscreen, width, height);

        glContext_ = platform_.createGLContext();
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
        platform_.swapWindow();
    }
}
