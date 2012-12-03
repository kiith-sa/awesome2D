//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Handles rendering of a single layer of pre-rendered output.
module awesome2d.renderlayer;


import gl3n.linalg;

import memory.memory;
import video.exceptions;
import video.glslshader;

/// Handles rendering of a single layer of pre-rendered output.
///
/// E.g. diffuse, normals, etc.
abstract class RenderLayer
{
    /// Called before rendering to set the projection matrix, if used by the layer's shader.
    @property void projectionMatrix(ref const mat4 rhs) @safe pure nothrow;
    /// Called before rendering to set the modelview matrix, if used by the layer's shader.
    @property void modelViewMatrix(ref const mat4 rhs) @safe pure nothrow;
    /// Called before rendering to set the normal matrix, if used by the layer's shader.
    @property void normalMatrix(ref const mat3 rhs) @safe pure nothrow;
    /// Get a reference to the internal shader program (for vertex buffer drawing).
    @property GLSLShaderProgram* shaderProgram() @safe pure nothrow;

    /// Called before rendering to this layer.
    void startRender();
    /// Called after rendering to this layer.
    void endRender();
}

/// Render layer that renders RGBA diffuse color.
class DiffuseColorRenderLayer: RenderLayer
{
private:
    /// Shader program doing the rendering.
    GLSLShaderProgram* shaderProgram_;
    /// Handle to the projection matrix uniform.
    uint projectionUniform_;
    /// Handle to the modelview matrix uniform.
    uint modelViewUniform_;

    /// Currently set projection (camera) matrix.
    mat4 projectionMatrix_;

    /// Currently set modelview matrix.
    mat4 modelViewMatrix_;

public:
    /// Construct a DiffuseColorRenderLayer using specified shader program.
    ///
    /// Params:  shaderProgram = Shader program to use. 
    ///                          The program must be empty (just constructed),
    ///                          and will be owned by the render layer, which
    ///                          will destroy it at its destruction.
    this(GLSLShaderProgram* shaderProgram)
    {
        try
        {
            shaderProgram_ = shaderProgram;
            string vertexShaderSource =
                [
                "attribute vec3 Position;"                                         ,
                "attribute vec2 TexCoord;"                                         ,
                ""                                                                 ,
                "varying vec2 frag_TexCoord;"                                      ,
                ""                                                                 ,
                "uniform mat4 ModelView;"                                          ,
                "uniform mat4 Projection;"                                         ,
                ""                                                                 ,
                "void main (void)"                                                 ,
                "{"                                                                ,
                "    frag_TexCoord = TexCoord;"                                    ,
                "    mat4 ModelViewProjection = ModelView * Projection;"           ,
                "    gl_Position = ModelViewProjection * vec4(Position, 1.0);"     ,
                "}"                                                                ,
                ].join("\n");

            string fragmentShaderSource =
                [
                "uniform sampler2D tex;"                                           ,
                "varying vec2 frag_TexCoord;"                                      ,
                ""                                                                 ,
                "void main (void)"                                                 ,
                "{"                                                                ,
                "    gl_FragColor = texture2D(tex, frag_TexCoord);"                ,
                "}"                                                                ,
                ].join("\n");

            const vertexShader   = shaderProgram_.addVertexShader(vertexShaderSource);
            const fragmentShader = shaderProgram_.addFragmentShader(fragmentShaderSource);
            shaderProgram_.lock();
            modelViewUniform_    = shaderProgram_.getUniformHandle("ModelView");
            projectionUniform_   = shaderProgram_.getUniformHandle("Projection");
        }
        catch(GLSLException e)
        {
            assert(false, "Builtin diffuse shader compilation or linking failed");
        }
    }

    /// Destroy the RenderLayer, freeing up used resources.
    ~this()
    {
        free(shaderProgram_);
    }

    override @property void projectionMatrix(ref const mat4 rhs) @safe pure nothrow
    {
        projectionMatrix_ = rhs;
    }

    override @property void modelViewMatrix(ref const mat4 rhs) @safe pure nothrow
    {
        modelViewMatrix_ = rhs;
    }


    override @property void normalMatrix(ref const mat3 rhs) @safe pure nothrow {}

    override @property GLSLShaderProgram* shaderProgram() @safe pure nothrow
    {
        return shaderProgram_;
    }

    override void startRender()
    {
        shaderProgram_.bind();
        shaderProgram_.setUniform(modelViewUniform_, modelViewMatrix_);
        shaderProgram_.setUniform(projectionUniform_, projectionMatrix_);
    }

    override void endRender()
    {
        shaderProgram_.release();
    }
}

//TODO NormalRenderLayer
//TODO CustomShaderLayer
