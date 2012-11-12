
//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// An OpenGL 2.0 backend using SDL 1.2 for OpenGL setup.
module video.sdlglrenderer;


import std.stdio;
import std.string;

import derelict.opengl.gl;
import derelict.sdl.sdl;

import color;
import video.exceptions;
import video.glrenderer;


/// An OpenGL 2.0 backend using SDL 1.2 for OpenGL setup.
class SDLGLRenderer : GLRenderer
{
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
    }

    /// Set video mode.
    ///
    /// This must be called exactly once after construction:
    ///
    /// In SDL 1.2, GL context is estabilished after setting the video mode;
    /// it can't be changed without replacing the GL context.
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
        uint red, green, blue, alpha;
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

        SDL_GL_SetAttribute(SDL_GL_RED_SIZE,     red);
        SDL_GL_SetAttribute(SDL_GL_GREEN_SIZE,   green);
        SDL_GL_SetAttribute(SDL_GL_BLUE_SIZE,    blue);
        SDL_GL_SetAttribute(SDL_GL_ALPHA_SIZE,   alpha);
        SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE,   24);
        SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
        const uint bitDepth = red + green + blue + alpha;

        uint flags = SDL_OPENGL;
        if(fullscreen){flags |= SDL_FULLSCREEN;}

        if(SDL_SetVideoMode(width, height, bitDepth, flags) is null)
        {
            string msg = std.string.format("Could not set video mode: %d %d %dbpp",
                                           width, height, bitDepth);
            writeln(msg);
            throw new RendererException(msg);
        }

        screenWidth_  = width;
        screenHeight_ = height;
        screenDepth_  = bitDepth;

        initGL();
    }

    override void swapBuffers()
    {
        const error = glGetError();
        SDL_GL_SwapBuffers();
    }
}
