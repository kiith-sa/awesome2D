
//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// A renderer based on OpenGL 2.0.
module video.glrenderer;


import std.conv;
import std.exception;
import std.stdio;
import std.typecons;

import derelict.opengl3.gl3;
import derelict.opengl3.gl;
import derelict.util.exception;

import color;
import image;
import memory.memory;
import util.linalg;
import video.blendmode;
import video.depthtest;
import video.exceptions;
import video.framebuffer;
import video.glslshader;
import video.glutils;
import video.gl2framebuffer;
import video.gl2glslshader;
import video.gl2indexbuffer;
import video.gl2texture;
import video.gl2vertexbuffer;
import video.renderer;
import video.texture;
import video.vertexattribute;
import video.vertexbuffer;
import video.indexbuffer;


/// A renderer based on OpenGL 2.1 (and ARB_framebuffer_object, for FBOs)
///
/// Written to be as "forward-compatible" with future GL as possible, to make
/// an eventual GL3/4 backend easier to implement.
///
/// Has to be further derived by a class that will handle video mode setup and
/// front/back buffer swapping.
abstract class GLRenderer : Renderer
{
protected:
    /// Video mode width in pixels.
    uint screenWidth_;
    /// Video mode height in pixels.
    uint screenHeight_;
    /// Video mode bits per pixel.
    uint screenDepth_;

    /// Currently used depth test mode.
    DepthTest depthTest_ = DepthTest.ReadWrite;

    /// Is the GL context initialized?
    bool glInitialized_ = false;

    /// Derelict OpenGL version.
    GLVersion glVersion_;

public:
    /// Construct a GLRenderer, loading the OpenGL library.
    this()
    {
        DerelictGL3.load();
        DerelictGL.load();
    }

    /// Destroy a GLRenderer.
    ~this()
    {
        writeln("Destroying GLRenderer");

        if(glInitialized_)
        {
            DerelictGL.unload();
            DerelictGL3.unload();
            glInitialized_ = false;
        }
    }

    override void testDrawTriangle()
    {
        // Test vertex struct.
        struct TestVertex
        {
            vec3 position;
            vec2 texCoord;
            vec3 color;
            this(const vec3 position, const vec2 texCoord, const vec3 color)
            {
                this.position = position;
                this.texCoord = texCoord;
                this.color    = color;
            }

            mixin VertexAttributes!(vec3, AttributeInterpretation.Position,
                                    vec2, AttributeInterpretation.TexCoord,
                                    vec3, AttributeInterpretation.Color);
        }

        pushBlendMode(BlendMode.Alpha);

        // Set up the modelViewProjection matrix.
        const viewOffset = vec2(0.0f, 0.0f);
        const viewZoom   = 1.0f;
        const modelView  =
            mat4.translation(viewOffset.x / screenWidth_,
                             viewOffset.y / screenHeight_, 0.0f);
        // near,far will have to be set from -1.0f,1.0f to something serious 
        // for 3D loading
        const projection =
            mat4.orthographic(0.0f, screenWidth_ / viewZoom, screenHeight_ / viewZoom,
                              0.0f, -1.0f, 1.0f);
        const modelViewProjection = modelView * projection;

        // Shader source code.
        string vertexShaderSource = 
            "attribute vec3 Position;\n" ~
            "attribute vec2 TexCoord;\n" ~
            "attribute vec3 Color;\n" ~
            "\n" ~
            "varying vec2 out_texcoord;\n" ~
            "varying vec4 out_color;\n" ~
            "\n" ~
            "uniform mat4 mvp_matrix;\n" ~
            "\n" ~
            "void main (void)\n" ~
            "{\n" ~
            "    out_texcoord = TexCoord;\n" ~
            "    out_color = vec4(Color, 1.0);\n" ~
            "    gl_Position = mvp_matrix * vec4(Position, 1.0);\n" ~
            "}\n";

        string vertexShaderSource2 = 
            "attribute vec3 Position;\n" ~
            "attribute vec2 TexCoord;\n" ~
            "attribute vec3 Color;\n" ~
            "\n" ~
            "varying vec2 out_texcoord;\n" ~
            "varying vec4 out_color;\n" ~
            "\n" ~
            "uniform mat4 mvp_matrix;\n" ~
            "\n" ~
            "void main (void)\n" ~
            "{\n" ~
            "    out_texcoord = TexCoord;\n" ~
            "    out_color = vec4(Color.r, Color.g, 1.0, 0.5);\n" ~
            "    gl_Position = mvp_matrix * vec4(Position.x, 200.0 + Position.y, Position.z + 0.1, 1);\n" ~
            "}\n";

        string fragmentShaderSource = 
            "uniform sampler2D tex;\n" ~
            "varying vec2 out_texcoord;\n" ~
            "varying vec4 out_color;\n" ~
            "\n" ~
            "void main (void)\n" ~
            "{\n" ~
            "    gl_FragColor = texture2D(tex, out_texcoord) * out_color;\n" ~
            "}\n";

        // Init shader program.
        GLSLShaderProgram* shaderProgram = createGLSLShader();
        const vertexShader = shaderProgram.addVertexShader(vertexShaderSource);
        const vertexShader2 = shaderProgram.addVertexShader(vertexShaderSource2);
        const fragmentShader = shaderProgram.addFragmentShader(fragmentShaderSource);

        // Init vertex buffer.
        auto vertexBuffer = createVertexBuffer!TestVertex(PrimitiveType.Triangles);
        alias TestVertex V;
        with(*vertexBuffer)
        {
            addVertex(V(vec3(0.0f,   0.0f,   0.0f), vec2(0.0f, 0.0f), vec3(1.0f, 0.0f, 0.0f)));
            addVertex(V(vec3(0.0f,   100.0f, 0.0f), vec2(0.0f, 1.0f), vec3(0.0f, 0.0f, 1.0f)));
            addVertex(V(vec3(800.0f, 600.0f, 0.0f), vec2(1.9f, 1.9f), vec3(0.0f, 1.0f, 0.0f)));
            addVertex(V(vec3(800.0f, 0.0f, 0.0f),   vec2(1.9f, 0.0f), vec3(1.0f, 1.0f, 1.0f)));
        }
        vertexBuffer.lock();

        // Init index buffer.
        auto indexBuffer = createIndexBuffer();
        indexBuffer.addIndex(0);
        indexBuffer.addIndex(1);
        indexBuffer.addIndex(2);
        indexBuffer.addIndex(0);
        indexBuffer.addIndex(2);
        indexBuffer.addIndex(3);
        indexBuffer.lock();


        // Init texture.
        auto image = Image(128, 128, ColorFormat.RGBA_8);
        image.generateCheckers(16);
        auto texture = 
            createTexture(image, TextureParams().filtering(TextureFiltering.Nearest));
        texture.bind(0);


        // Use vertex shader 1.
        shaderProgram.disableVertexShader(vertexShader2);
        shaderProgram.lock();

        // Upload any uniforms.
        const modelViewProjectionUniform = 
            shaderProgram.getUniformHandle("mvp_matrix");
        shaderProgram.bind();
        shaderProgram.setUniform(modelViewProjectionUniform, 
                                 modelViewProjection);

        // Draw.
        drawVertexBuffer(vertexBuffer, indexBuffer, shaderProgram);
        shaderProgram.release();



        // Modify the program (swap to vertex shader 2)
        shaderProgram.unlock();
        shaderProgram.enableVertexShader(vertexShader2);
        shaderProgram.disableVertexShader(vertexShader);
        shaderProgram.lock();
        shaderProgram.bind();

        // Upload any uniforms.
        shaderProgram.setUniform(modelViewProjectionUniform, 
                                 modelViewProjection);

        // Draw.
        drawVertexBuffer(vertexBuffer, indexBuffer, shaderProgram);
        shaderProgram.release();

        popBlendMode();

        // Clean up.
        free(texture);
        free(indexBuffer);
        free(vertexBuffer);
        free(shaderProgram);
    }

    override void renderFrame(bool delegate(Renderer) drawPartial)
    {
        glClearColor(0, 0, 0, 0);
        glClear(GL_COLOR_BUFFER_BIT);
        glClear(GL_DEPTH_BUFFER_BIT);
        glEnable(GL_CULL_FACE);
        glCullFace(GL_BACK);
        setupViewport();
        // TODO (low-priority):
        // Use FBOs for drawing and suspend drawing if too slow
        // like in Stellarium.
        while (true)
        {
            const doneDrawing = drawPartial(this);
            if(doneDrawing) 
            {
                swapBuffers();
                break;
            }
        }
        const error = glGetError();
        if(error != GL_NO_ERROR)
        {
            writeln("GL error at the end of a frame: ", to!string(error));
        }
    }

    override FrameBuffer* createFrameBuffer
        (const uint width, const uint height,
         ColorFormat format = ColorFormat.RGBA_8, 
         Flag!"useDepth" useDepth = Yes.useDepth)
    {
        auto result = alloc!FrameBuffer;
        try
        {
            constructFrameBufferGL2(*result, width, height, format, useDepth);
        }
        catch(FrameBufferInitException e)
        {
            free(result);
            return null;
        }
        return result;
    }

    override IndexBuffer* createIndexBuffer()
    {
        auto result = alloc!IndexBuffer;
        constructIndexBufferGL2(*result);
        return result;
    }

    override Texture* createTexture
        (ref const Image image, const TextureParams params)
    {
        auto result = alloc!Texture;
        try
        {
            constructTextureGL2(*result, image, params);
        }
        catch(TextureInitException e)
        {
            free(result);
            return null;
        }
        return result;
    }

    override GLSLShaderProgram* createGLSLShader()
    {
        auto result = alloc!GLSLShaderProgram;
        constructGLSLShaderGL2(*result);
        return result;
    }

    override bool isGLSLSupported() @safe pure nothrow const
    {
        return true;
    }

    override uint textureUnitCount() const
    {
        int textureUnitCount;
        glGetIntegerv(GL_MAX_TEXTURE_IMAGE_UNITS, &textureUnitCount);
        return textureUnitCount;
    }

    override @property vec2u viewportSize() @safe pure nothrow const
    {
        return vec2u(screenWidth_, screenHeight_);
    }

    override @property void depthTest(const DepthTest depthTest)
    {
        depthTest_ = depthTest;
        if(!glInitialized_){return;}
        final switch(depthTest_)
        {
            case DepthTest.Disabled:
                glDisable(GL_DEPTH_TEST);
                break;
            case DepthTest.ReadWrite:
                glEnable(GL_DEPTH_TEST);
                glDepthFunc(GL_LEQUAL);
                break;
        }
    }

protected:
    override void createVertexBufferBackend(ref VertexBufferBackend backend,
                                            ref const VertexAttributeSpec attributeSpec)
    {
        constructVertexBufferBackendGL2(backend, attributeSpec);
    }

    override void drawVertexBufferBackend(ref VertexBufferBackend backend,
                                          IndexBuffer* indexBuffer, 
                                          GLSLShaderProgram* shaderProgram,
                                          const uint first,
                                          const uint elements,
                                          const uint minIndex,
                                          const uint maxIndex)
    {
        //debugSetupGLState();
        backend.drawVertexBufferGL2(indexBuffer, *shaderProgram, first, elements, 
                                    minIndex, maxIndex);
        //debugRestoreGLState();
    }

    override @property void blendModeChange(const BlendMode blendMode) @trusted
    {
        if(!glInitialized_){return;}
        final switch(blendMode)
        {
            case BlendMode.None:
                glDisable(GL_BLEND);
                break;
            case BlendMode.Add:
                alias derelict.opengl3.deprecatedConstants.GL_ONE GL_ONE;
                glBlendFunc(GL_ONE, GL_ONE);
                glEnable(GL_BLEND);
                break;
            case BlendMode.Alpha:
                glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
                glEnable(GL_BLEND);
                break;
            case BlendMode.Multiply:
                glBlendFunc(GL_SRC_COLOR, GL_ONE_MINUS_SRC_COLOR);
                glEnable(GL_BLEND);
                break;
        }
    }

    /// Initialize OpenGL context.
    void initGL()
    {
        scope(failure){writeln("OpenGL initialization failed");}
        try
        {
            //Loads the newest available OpenGL version
            glVersion_ = DerelictGL3.reload();
        }
        catch(DerelictException e)
        {
            throw new RendererInitException
                ("Could not load OpenGL: " ~ e.msg ~
                 "\nPerhaps you need to install new graphics drivers?");
        }
        enforce(glIsExtensionAvailable("GL_ARB_framebuffer_object"),
                new RendererInitException(
                "Required GL extension GL_ARB_framebuffer_object is not supported"));

        if(glVersion_ < GLVersion.GL20)
        {
            throw new RendererInitException
                ("OpenGL initialization failed: OpenGL 2.0 not supported." ~
                 "\nPerhaps you need to install new graphics drivers?");
        }

        glClearColor(0.0f, 0.0f, 0.0f, 0.0f);

        string errorMsg;
        if(glErrorOccured(errorMsg))
        {
            writeln("GL error after GL initialization: ", errorMsg);
        }

        glInitialized_ = true;

        depthTest(depthTest_);
        blendModeChange(blendModeStack_.back);
    }

    /// Swap the front and back buffer. 
    ///
    /// Has to be done by the library that set up GL (e.g. SDL).
    void swapBuffers();

private:
    /// Debugging: Set up GL state before drawing.
    ///
    /// Allows us to encapsulate GL state, avoiding leaking unexpected state 
    /// between draws.
    void debugSetupGLState()
    {
        glEnable(GL_CULL_FACE);
        glCullFace(GL_BACK);
        blendModeChange(blendModeStack_.back);
        depthTest(depthTest_);
    }

    /// Debugging: Restore GL state after drawing.
    void debugRestoreGLState()
    {
        glDisable(GL_CULL_FACE);
        glDisable(GL_BLEND);
        glDisable(GL_DEPTH_TEST);
    }

    /// Set up OpenGL viewport.
    final void setupViewport()
    {
        glViewport(0, 0, screenWidth_, screenHeight_);
    }
}
