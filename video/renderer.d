
//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Renderer API (central class of the video subsystem).
module video.renderer;


import std.conv;
import std.stdio;
import std.typecons;

import gl3n.linalg;

import color;
import image;
import memory.memory;

import containers.vector;
import platform.platform;
public import video.blendmode;
public import video.depthtest;
import video.exceptions;
import video.framebuffer;
import video.glslshader;
import video.indexbuffer;
import video.primitivetype;
import video.texture;
import video.vertexattribute;
import video.vertexbuffer;


/// Renderer API (central class of the video subsystem).
///
/// Constructs all other video API classes such as vertex buffers, textures, 
/// etc.
abstract class Renderer
{
protected:
    /// Vector of blend modes used as a stack. The last item is the current blend mode.
    containers.vector.Vector!BlendMode blendModeStack_;

public:
    /// Constructor.
    ///
    /// Throws: RendererInitException on failure.
    this()
    {
        pushBlendMode(BlendMode.None);
    }

    /// Create a framebuffer object.
    ///
    /// The framebuffer must be destroyed by the user before the renderer is 
    /// destroyed.
    ///
    /// Params:  width    = Width of the framebuffer in pixels.
    ///          height   = Height of the framebuffer in pixels.
    ///          format   = Color format of the framebuffer.
    ///          useDepth = Should the framebuffer have a depth buffer attached?
    ///                     (required to draw to the framebuffer with depth test).
    ///
    /// Returns: Pointer to the new framebuffer, or null on failure.
    FrameBuffer* createFrameBuffer(const uint width, const uint height,
                                   ColorFormat format = ColorFormat.RGBA_8,
                                   Flag!"useDepth" = Yes.useDepth);

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
    /// The vertex buffer must be destroyed by the user before
    /// the renderer is destroyed.
    VertexBuffer!V* createVertexBuffer(V)(const PrimitiveType primitiveType)
    {
        auto result = alloc!(VertexBuffer!V)(primitiveType);
        createVertexBufferBackend(result.backend_, V.vertexAttributeSpec_);
        return result;
    }

    /// Create a 2D texture, loading from specified image.
    ///
    /// The texture must be destroyed by the user before the renderer is 
    /// destroyed. 
    ///
    /// Pixel format of the texture will be based on image format of the image.
    ///
    /// Params:  image  = Image to load from.
    ///          params = Texture parameters (e.g. filtering).
    ///
    /// Returns: Pointer to the new texture, or null on failure.
    Texture* createTexture(const ref Image image, 
                           const TextureParams params = TextureParams.init);

    /// Create a GLSL shader program.
    GLSLShaderProgram* createGLSLShader();

    /// Draw a vertex buffer, optionally with an index buffer specifying vertices to draw.
    ///
    /// Params: vertexBuffer  = Vertex buffer to draw from.
    ///                         Must be bound.
    ///         indexBuffer   = Index buffer specifying vertices to draw.
    ///                         If non-null, must be bound.
    ///                         If null, the vertices are drawn consecutively.
    ///         shaderProgram = Shader program to use for drawing.
    ///                         Must be bound.
    void drawVertexBuffer(V)(VertexBuffer!V* vertexBuffer,
                             IndexBuffer* indexBuffer,
                             GLSLShaderProgram* shaderProgram)
    {
        assert(vertexBuffer  !is null, "Vertex buffer must be specified when drawing");
        assert(shaderProgram !is null, "Shader program must be specified when drawing");
        drawVertexBufferBackend(vertexBuffer.backend_, indexBuffer, shaderProgram, 0, 
                                cast(uint)(indexBuffer is null ? vertexBuffer.length 
                                                               : indexBuffer.length));
    }

    /// Draw a part of a vertex buffer, optionally with an index buffer specifying vertices to draw.
    ///
    /// Params: vertexBuffer  = Vertex buffer to draw from.
    ///                         Must be bound.
    ///         indexBuffer   = Index buffer specifying vertices to draw.
    ///                         If non-null, must be bound.
    ///                         If null, the vertices are drawn consecutively.
    ///         shaderProgram = Shader program to use for drawing.
    ///                         Must be bound.
    ///         first         = Index of the first vertex of vertexBuffer to use
    ///                         if indexBuffer is null, or the first index of
    ///                         indexBuffer to use otherwise.
    ///         elements      = Number of vertices to draw.
    void drawVertexBuffer(V)(VertexBuffer!V* vertexBuffer,
                             IndexBuffer* indexBuffer,
                             GLSLShaderProgram* shaderProgram,
                             const uint first, 
                             const uint elements)
    {
        assert(vertexBuffer  !is null, "Vertex buffer must be specified when drawing");
        assert(shaderProgram !is null, "Shader program must be specified when drawing");
        drawVertexBufferBackend(vertexBuffer.backend_, indexBuffer, shaderProgram, 
                                first, elements);
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
    bool isGLSLSupported() @safe pure nothrow const;

    /// Get the number of texture units on the machine.
    ///
    /// This is always at least 2.
    @property uint textureUnitCount() const;

    /// Get viewport size in pixels.
    @property vec2u viewportSize() @safe pure nothrow const;

    /// Push a blend mode to use for following draws to the stack.
    ///
    /// The default blend mode is BlendMode.None.
    ///
    /// popBlendMode() will return to the previous blend mode.
    final void pushBlendMode(const BlendMode blendMode) @safe
    {
        blendModeStack_ ~= blendMode;
        blendModeChange(blendMode);
    }

    /// Pop a blend mode from the blend mode stack, reverting to the previous blend mode.
    final void popBlendMode() @safe
    {
        assert(blendModeStack_.length >= 1,
               "Trying to pop the bottommost blend mode from the blend mode stack");
        blendModeStack_.popBack();
        blendModeChange(blendModeStack_.back);
    }

    /// Get the currently set blend mode.
    final @property BlendMode blendMode() const pure nothrow {return blendModeStack_.back;}

    /// Set depth test to use for following draws.
    @property void depthTest(const DepthTest depthTest);

    /// Set video mode.
    ///
    /// Params: width      = Video mode width in pixels.
    ///         height     = Video mode height in pixels.
    ///         format     = Video mode color format.
    ///                      Only RGB_565 and RGBA_8 are supported.
    ///         fullscreen = Use a fullscreen video mode?
    void setVideoMode(const uint width, const uint height, 
                      const ColorFormat format, const bool fullscreen);

protected:
    /// Initialize the passed vertex buffer backend.
    ///
    /// Params:  backend       = Backend to initialize.
    ///          attributeSpec = Attribute specification of the vertex type
    ///                          stored in the buffer.
    void createVertexBufferBackend(ref VertexBufferBackend backend, 
                                   ref const VertexAttributeSpec attributeSpec);


    /// Implementation of drawVertexBuffer. (Separate due to template-virtual incompatibility)
    void drawVertexBufferBackend(ref VertexBufferBackend backend,
                                 IndexBuffer* indexBuffer,
                                 GLSLShaderProgram* shaderProgram,
                                 const uint first,
                                 const uint elements);

    /// Called when the blend mode changes to specified blend mode.
    @property void blendModeChange(const BlendMode blendMode) @trusted;
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
         * Params:  platform   = Platform handling window management. Must match
         *                       the renderer type, e.g. SDL2Platform for 
         *                       SDL2GLRenderer.
         *          width      = Width of initial video mode.
         *          height     = Height of initial video mode.
         *          format     = Color format of initial video mode.
         *          fullscreen = Should initial video mode be fullscreen?
         *
         * Returns: Produced renderer or null on error.
         */
        Renderer produce(R)(Platform platform, const uint width, const uint height, 
                            const ColorFormat format, const bool fullscreen)
            if(is(R: Renderer))
        {
            auto typeString = typeid(R).toString();
            try
            {
                renderer_ = new R(platform);
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
