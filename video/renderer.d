
//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Renderer API (central class of the video subsystem).
module video.renderer;


import std.conv;
import std.stdio;

import color;
import math.vector2;
import image;

import video.blendmode;
import video.exceptions;
import video.glslshader;
import video.texture;
import video.vertexbuffer;
import video.indexbuffer;


/// Renderer API (central class of the video subsystem).
///
/// Constructs all other video API classes such as vertex buffers, textures, 
/// etc.
abstract class Renderer
{
    // TODO screenshot (for output)
    // TODO render to texture 
    //      (start, setting a texture, then all draws go to that texture 
    //       through a FBO, then end)

    /// Constructor.
    ///
    /// Throws: RendererInitException on failure.
    this()
    {
    }

    /// Construct an empty index buffer and return a pointer to it.
    ///
    /// The index buffer must be destroyed by the user before
    /// the renderer is destroyed.
    IndexBuffer* createIndexBuffer();

    /// Construct an empty vertex buffer and return a pointer to it.
    ///
    /// Params: primitiveType = Determines which graphics primitive type 
    ///                         should the vertices in this buffer form.
    ///
    /// The index buffer must be destroyed by the user before
    /// the renderer is destroyed.
    VertexBuffer!V* createVertexBuffer(V)(const PrimitiveType primitiveType)
    {
        assert(false, "TODO");
    }

    /// Create a 2D texture, loading from specified image.
    ///
    /// The texture must be destroyed by the user before the renderer is 
    /// destroyed.
    Texture* createTexture(const ref Image image);

    /// Create a GLSL shader program.
    GLSLShaderProgram* createGLSLShader();

    /// Draw specified vertex buffer.
    ///
    /// The entire buffer is drawn in order of the vertices.
    void drawVertexBuffer(V)(VertexBuffer!V* vertexBuffer)
    {
        assert(false, "TODO");
    }

    /// Draw specified vertex buffer with an index buffer specifying vertices to draw.
    ///
    /// Params: vertexBuffer = Vertex buffer to draw from.
    ///         indexBuffer  = Index buffer specifying vertices to draw.
    void drawVertexBuffer(V)(VertexBuffer!V* vertexBuffer, IndexBuffer* indexBuffer)
    {
        assert(false, "TODO");
    }

    /// A test function that draws a triangle.
    void testDrawTriangle();

    /// Render a single frame.
    ///
    /// Params: drawPartial = A function using the renderer to draw the scene.
    ///                       All rendering must happen within this function.
    ///                       If the drawPartial returns false, the frame is
    ///                       not yet done drawing - this allows a backend
    ///                       to split a frame when FPS is too low.
    ///                       When the entire scene is drawn, drawPartial should
    ///                       return true.
    void renderFrame(bool delegate(Renderer) drawPartial);

    /// Are GLSL shaders supported?
    /// 
    /// Shaders are required, but alternative backends might support e.g. HLSL in future.
    /// 
    bool isGLSLSupported() const;

    /// Get viewport size in pixels.
    @property Vector2u viewportSize() const;

    /// Set blend mode to use for following draws.
    void setBlendMode(const BlendMode blendMode);

    /// Set video mode.
    ///
    /// Params: width      = Video mode width in pixels.
    ///         height     = Video mode height in pixels.
    ///         format     = Video mode color format.
    ///                      Only RGB_565 and RGBA_8 are supported.
    ///         fullscreen = Use a fullscreen video mode?
    void setVideoMode(const uint width, const uint height, 
                      const ColorFormat format, const bool fullscreen);

}


///Class managing lifetime and dependencies of video driver.
class RendererContainer
{
    private:
        ///Managed renderer.
        Renderer renderer_;

    public:
        /**
         * Construct a RendererContainer.
         *
         * Throws:  RendererInitException on failure.
         */
        this()
        {
        }

        /**
         * Initialize renderer of specified type and return a reference to it.
         *
         * Params:  width      = Width of initial video mode.
         *          height     = Height of initial video mode.
         *          format     = Color format of initial video mode.
         *          fullscreen = Should initial video mode be fullscreen?
         *
         * Returns: Produced renderer or null on error.
         */
        Renderer produce(R)(const uint width, const uint height, 
                            const ColorFormat format, const bool fullscreen)
            if(is(R: Renderer))
        {
            auto typeString = typeid(R).toString();
            try
            {
                renderer_ = new R();
                renderer_.setVideoMode(width, height, format, fullscreen);
            }
            catch(RendererInitException e)
            {
                clear(renderer_);
                renderer_ = null;
                writeln("Failed to construct a " ~ typeString ~ ": " ~ e.msg);
                return null;
            }

            return renderer_;
        }

        ///Destroy the video driver.
        void destroy()
        {
            clear(renderer_);
            renderer_ = null;
        }

        /**
         * Destroy the container.
         *
         * Destroys any video driver dependencies.
         * Video driver must be destroyed first by calling destroy().
         */
        ~this()
        in
        {
            assert(renderer_ is null,
                   "Renderer must be destroyed before its container");
        }
        body
        {
        }
}
