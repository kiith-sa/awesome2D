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
    @property void projectionMatrix(ref const mat4 rhs) @safe pure nothrow {};
    /// Called before rendering to set the model matrix, if used by the layer's shader.
    @property void modelMatrix(ref const mat4 rhs) @safe pure nothrow {};
    /// Called before rendering to set the view matrix, if used by the layer's shader.
    @property void viewMatrix(ref const mat4 rhs) @safe pure nothrow {};
    /// Called before rendering to set the normal matrix, if used by the layer's shader.
    @property void normalMatrix(ref const mat3 rhs) @safe pure nothrow {};
    /// Called before rendering to set the maximum distance of a vertex from origin.
    @property void maxExtentFromOrigin(const float rhs) pure nothrow {}
    /// Get a reference to the internal shader program (for vertex buffer drawing).
    @property GLSLShaderProgram* shaderProgram() @safe pure nothrow;

    /// Called before rendering to this layer.
    void startRender();
    /// Called after rendering to this layer.
    void endRender();
}

/// Base class for shader-based render layer, with common uniforms, etc.
abstract class ShaderRenderLayer: RenderLayer
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
    /// Construct the ShaderRenderLayer.
    ///
    /// Params:  shaderProgram = Shader program used by the layer. Must be already initialized
    ///                          with vertex and fragment shaders.
    this(GLSLShaderProgram* shaderProgram)
    {
        shaderProgram_     = shaderProgram;
        modelUniform_      = shaderProgram_.getUniformHandle("Model");
        viewUniform_       = shaderProgram_.getUniformHandle("View");
        projectionUniform_ = shaderProgram_.getUniformHandle("Projection");
    }

    /// Destroy the ShaderRenderLayer, freeing up used resources.
    ~this()
    {
        free(shaderProgram_);
    }

    final override @property void projectionMatrix(ref const mat4 rhs) @safe pure nothrow
    {
        projectionMatrix_ = rhs;
    }

    final override @property void modelMatrix(ref const mat4 rhs) @safe pure nothrow
    {
        modelMatrix_ = rhs;
    }

    final override @property void viewMatrix(ref const mat4 rhs) @safe pure nothrow
    {
        viewMatrix_ = rhs;
    }

    final override @property GLSLShaderProgram* shaderProgram() @safe pure nothrow
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

/// Render layer that renders RGBA diffuse color.
class DiffuseColorRenderLayer: ShaderRenderLayer
{
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
                "uniform mat4 Model;"                                              ,
                "uniform mat4 View;"                                               ,
                "uniform mat4 Projection;"                                         ,
                ""                                                                 ,
                "void main (void)"                                                 ,
                "{"                                                                ,
                "    frag_TexCoord = TexCoord;"                                    ,
                "    mat4 ModelViewProjection = Projection * View * Model;"        ,
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

            const vertexShader   = shaderProgram.addVertexShader(vertexShaderSource);
            const fragmentShader = shaderProgram.addFragmentShader(fragmentShaderSource);
            shaderProgram.lock();
            super(shaderProgram);
        }
        catch(GLSLException e)
        {
            assert(false, "Builtin diffuse shader compilation or linking failed");
        }
    }
}

/// Render layer that renders normals as RGB coords.
class NormalRenderLayer: ShaderRenderLayer
{
private:
    /// Handle to the normal matrix uniform.
    uint normalMatrixUniform_;

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
                "attribute vec3 Position;\n",
                "attribute vec3 Normal;\n",
                "\n",
                "uniform mat4 Model, View, Projection;\n",
                "uniform mat3 NormalMatrix;\n",
                "\n",
                "varying vec3 frag_Normal;\n",
                "void main(void)\n",
                "{\n",
                "    mat4 ModelViewProjection = Projection * View * Model;\n",
                "    frag_Normal   = normalize(NormalMatrix * Normal);\n"
                "    gl_Position = ModelViewProjection * vec4(Position, 1.0);\n",
                "}\n"
                ].join("\n");

            string fragmentShaderSource =
                [
                "varying vec3 frag_Normal;\n",
                "\n",
                "void main(void)\n",
                "{\n",
                "    vec3 normalDirection = normalize(frag_Normal);\n",
                // Normals can be negative; so we map their coordinates to (0.0-1.0).
                "    gl_FragColor = vec4((vec3(1.0, 1.0, 1.0) + normalDirection) * 0.5, 1.0);\n",
                "}\n",
                ].join("\n");

            const vertexShader   = shaderProgram.addVertexShader(vertexShaderSource);
            const fragmentShader = shaderProgram.addFragmentShader(fragmentShaderSource);
            shaderProgram.lock();
            super(shaderProgram);
            normalMatrixUniform_ = shaderProgram.getUniformHandle("NormalMatrix");
        }
        catch(GLSLException e)
        {
            assert(false, "Builtin diffuse shader compilation or linking failed");
        }
    }

    final override @property void normalMatrix(ref const mat3 rhs) @safe pure nothrow 
    {
        normalMatrix_ = rhs;
    }

    override void startRender()
    {
        super.startRender();
        shaderProgram_.setUniform(normalMatrixUniform_, normalMatrix_);
    }
}


/// Render layer that renders offsets relative to the model's position.
class OffsetRenderLayer: ShaderRenderLayer
{
private:
    /// Handle to the maximum extent uniform.
    uint maxExtentFromOriginUniform_;
    /// Maximum distance of a vertex from origin.
    ///
    /// In the rendered offset output, the minimum value (0) for each
    /// axis (X, Y, Z being R, G, B, respectively) maps to -maxExtentFromOrigin_,
    /// while the maximum value (255) maps to +maxExtentFromOrigin_.
    float maxExtentFromOrigin_;

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
                "attribute vec4 Position;\n",
                "varying vec3 frag_Position;\n",
                "uniform mat4 Model, View, Projection;\n",
                "\n",
                "void main()\n",
                "{\n",
                "    frag_Position = vec3(Model * Position);\n",
                "    mat4 ModelViewProjection = Projection * View * Model;\n",
                "    gl_Position = ModelViewProjection * Position;\n",
                "}\n"
                ].join("\n");

            string fragmentShaderSource =
                [
                "varying vec3 frag_Position;\n",
                "uniform mat4 Model, View, Projection;\n",
                "uniform float MaxExtentFromOrigin;\n",
                "\n",
                "void main()\n",
                "{\n",
                // Map [-maxExtentFromOrigin_ .. maxExtentFromOrigin_] to [0 .. 1]
                "    gl_FragColor = vec4((frag_Position / (2.0 * MaxExtentFromOrigin)) + 1.0, 1.0);\n",
                "}\n"
                ].join("\n");

            const vertexShader   = shaderProgram.addVertexShader(vertexShaderSource);
            const fragmentShader = shaderProgram.addFragmentShader(fragmentShaderSource);
            shaderProgram.lock();
            maxExtentFromOriginUniform_ = shaderProgram.getUniformHandle("MaxExtentFromOrigin");
            super(shaderProgram);
        }
        catch(GLSLException e)
        {
            assert(false, "Builtin diffuse shader compilation or linking failed");
        }
    }

    final override @property void maxExtentFromOrigin(const float rhs) pure nothrow 
    {
        maxExtentFromOrigin_ = rhs;
    }

    override void startRender()
    {
        super.startRender();
        shaderProgram_.setUniform(maxExtentFromOriginUniform_, maxExtentFromOrigin_);
    }
}
