
//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


module video.renderer;

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
}
