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
    /// Called before rendering to set the model matrix, if used by the layer's shader.
    @property void modelMatrix(ref const mat4 rhs) @safe pure nothrow;
    /// Called before rendering to set the view matrix, if used by the layer's shader.
    @property void viewMatrix(ref const mat4 rhs) @safe pure nothrow;
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
    /// Handle to the model matrix uniform.
    uint modelUniform_;
    /// Handle to the view matrix uniform.
    uint viewUniform_;

    /// Currently set projection (camera) matrix.
    mat4 projectionMatrix_;
    /// Currently set model matrix.
    mat4 modelMatrix_;
    /// Currently set view matrix.
    mat4 viewMatrix_;

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
                "uniform mat4 Model;"                                          ,
                "uniform mat4 View;"                                          ,
                "uniform mat4 Projection;"                                         ,
                ""                                                                 ,
                "void main (void)"                                                 ,
                "{"                                                                ,
                "    frag_TexCoord = TexCoord;"                                    ,
                "    mat4 ModelViewProjection = Projection * View * Model;"           ,
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
            modelUniform_      = shaderProgram_.getUniformHandle("Model");
            viewUniform_       = shaderProgram_.getUniformHandle("View");
            projectionUniform_ = shaderProgram_.getUniformHandle("Projection");
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

    override @property void modelMatrix(ref const mat4 rhs) @safe pure nothrow
    {
        modelMatrix_ = rhs;
    }

    override @property void viewMatrix(ref const mat4 rhs) @safe pure nothrow
    {
        viewMatrix_ = rhs;
    }

    override @property void normalMatrix(ref const mat3 rhs) @safe pure nothrow {}

    override @property GLSLShaderProgram* shaderProgram() @safe pure nothrow
    {
        return shaderProgram_;
    }

    override void startRender()
    {
        shaderProgram_.bind();
        shaderProgram_.setUniform(modelUniform_, modelMatrix_);
        shaderProgram_.setUniform(viewUniform_, viewMatrix_);
        shaderProgram_.setUniform(projectionUniform_, projectionMatrix_);
    }

    override void endRender()
    {
        shaderProgram_.release();
    }
}

/// Render layer that renders normals as RGB coords.
class NormalRenderLayer: RenderLayer
{
private:
    /// Shader program doing the rendering.
    GLSLShaderProgram* shaderProgram_;
    /// Handle to the projection matrix uniform.
    uint projectionUniform_;
    /// Handle to the model matrix uniform.
    uint modelUniform_;
    /// Handle to the view matrix uniform.
    uint viewUniform_;
    /// Handle to the normal matrix uniform.
    uint normalMatrixUniform_;

    /// Currently set projection (camera) matrix.
    mat4 projectionMatrix_;
    /// Currently set model matrix.
    mat4 modelMatrix_;
    /// Currently set view matrix.
    mat4 viewMatrix_;
    /// Currently set normal matrix.
    mat3 normalMatrix_;

public:
    /// Construct a NormalRenderLayer using specified shader program.
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
                "attribute vec3 Position;",
                "attribute vec3 Normal;",
                "",
                "uniform mat4 Model, View, Projection;",
                "uniform mat3 NormalMatrix;",
                "",
                "varying vec3 frag_Normal;",
                "void main(void)",
                "{",
                "    mat4 ModelViewProjection = Projection * View * Model;",
                "    frag_Normal   = normalize(NormalMatrix * Normal);"
                "    gl_Position = ModelViewProjection * vec4(Position, 1.0);",
                "}",
                ].join("\n");

            string fragmentShaderSource =
                [
                "varying vec3 frag_Normal;",
                "",
                "void main(void)",
                "{",
                "    vec3 normalDirection = normalize(frag_Normal);",
                // Normals can be negative; so we map their coordinates to (0.0-1.0).
                "    gl_FragColor = vec4((vec3(1.0, 1.0, 1.0) + normalDirection) * 0.5, 1.0);",
                "}",
                ].join("\n");

            const vertexShader   = shaderProgram_.addVertexShader(vertexShaderSource);
            const fragmentShader = shaderProgram_.addFragmentShader(fragmentShaderSource);
            shaderProgram_.lock();
            modelUniform_        = shaderProgram_.getUniformHandle("Model");
            viewUniform_         = shaderProgram_.getUniformHandle("View");
            projectionUniform_   = shaderProgram_.getUniformHandle("Projection");
            normalMatrixUniform_ = shaderProgram_.getUniformHandle("NormalMatrix");
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

    override @property void modelMatrix(ref const mat4 rhs) @safe pure nothrow
    {
        modelMatrix_ = rhs;
    }

    override @property void viewMatrix(ref const mat4 rhs) @safe pure nothrow
    {
        viewMatrix_ = rhs;
    }

    override @property void normalMatrix(ref const mat3 rhs) @safe pure nothrow 
    {
        normalMatrix_ = rhs;
    }

    override @property GLSLShaderProgram* shaderProgram() @safe pure nothrow
    {
        return shaderProgram_;
    }

    override void startRender()
    {
        shaderProgram_.bind();
        shaderProgram_.setUniform(modelUniform_,        modelMatrix_);
        shaderProgram_.setUniform(viewUniform_,         viewMatrix_);
        shaderProgram_.setUniform(projectionUniform_,   projectionMatrix_);
        shaderProgram_.setUniform(normalMatrixUniform_, normalMatrix_);
    }

    override void endRender()
    {
        shaderProgram_.release();
    }
}

//TODO OffsetLayer
