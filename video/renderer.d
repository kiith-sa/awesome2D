
//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


module video.renderer;

import std.stdio;

import color;
import math.vector2;
import image;

import video.blendmode;
import video.glslshader;
import video.texture;
import video.vertexbuffer;
import video.indexbuffer;

/// Exception thrown at renderer errors.
class RendererException : Exception 
{
    public this(string msg, string file = __FILE__, int line = __LINE__)
    {
        super(msg, file, line);
    }
}

abstract class Renderer
{
    /// Constructor.
    ///
    /// Throws: RendererException on failure.
    this()
    {
    }

    IndexBuffer* createIndexBuffer();

    VertexBuffer!V* createVertexBuffer(V)(const PrimitiveType primitiveType);

    void drawVertexBuffer(V)(ref VertexBuffer!V vertexBuffer);

    void drawVertexBuffer(V)(ref VertexBuffer!V vertexBuffer,
                             ref IndexBuffer indexBuffer);

    void renderFrame(void delegate() drawPartial);

    Texture* createTexture(const ref Image image);

    GLSLShader* createGLSLShader();

    /**
     * Are GLSL shaders supported?
     *
     * Shaders are required, but alternative backends might support e.g. HLSL in future.
     */
    bool isGLSLSupported() const;

    void setBlendMode(const BlendMode blendMode);

    @property Vector2u viewportSize() const;

    void setVideoMode(const uint width, const uint height, 
                      const ColorFormat format, const bool fullscreen);

}


import derelict.sdl.sdl;

abstract class GLRenderer : Renderer
{
protected:
    uint screenWidth_;
    uint screenHeight_;
    uint screenDepth_;

protected:
    void initGL()
    {
        // TODO
    }

    // TODO implement parent methods

    void swapBuffers();
}

// TEMP (Until all methods are implemented)
abstract
class SDLGLRenderer : GLRenderer
{
    this()
    {
        writeln("Initializing SDLGLRenderer");
        super();
    }

    ~this()
    {
        writeln("Destroying SDLGLRenderer");
    }
    
    override void setVideoMode(const uint width, const uint height, 
                               const ColorFormat format, const bool fullscreen)
    {
        assert(width >= 80 && width <= 65536, 
               "Can't set video mode with such ridiculous width");
        assert(height >= 60 && width <= 49152, 
               "Can't set video mode with such ridiculous height");

        //determine bit depths of color channels.
        uint red, green, blue, alpha;
        switch(format)
        {
            case ColorFormat.RGB_565:
                red = 5;
                green = 6;
                blue = 5;
                alpha = 0;
                break;
            case ColorFormat.RGBA_8:
                red = 8;
                green = 8;
                blue = 8;
                alpha = 8;
                break;
            default:
                assert(false, "Unsupported video mode color format");
        }

        SDL_GL_SetAttribute(SDL_GL_RED_SIZE, red);
        SDL_GL_SetAttribute(SDL_GL_GREEN_SIZE, green);
        SDL_GL_SetAttribute(SDL_GL_BLUE_SIZE, blue);
        SDL_GL_SetAttribute(SDL_GL_ALPHA_SIZE, alpha);
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
        SDL_GL_SwapBuffers();
    }
}
