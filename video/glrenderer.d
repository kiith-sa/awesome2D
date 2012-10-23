
//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// A renderer based on OpenGL 2.0.
module video.glrenderer;


import std.stdio;
import std.conv;

import derelict.opengl.gl;
import derelict.opengl.exttypes;
import derelict.opengl.extfuncs;
import derelict.util.exception;

import image;
import math.vector2;
import video.blendmode;
import video.exceptions;
import video.glslshader;
import video.renderer;
import video.texture;
import video.vertexbuffer;
import video.indexbuffer;


/// A renderer based on OpenGL 2.0.
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

    /// Currently enabled blending mode.
    BlendMode blendMode_;

    /// Is the GL context initialized?
    bool glInitialized_ = false;

    /// Derelict OpenGL version.
    GLVersion glVersion_;

public:
    /// Construct a GLRenderer, loading the OpenGL library.
    this()
    {
        DerelictGL.load();
    }

    /// Destroy a GLRenderer.
    ~this()
    {
        writeln("Destroying GLRenderer");

        if(glInitialized_)
        {
            DerelictGL.unload();
            glInitialized_ = false;
        }
    }

    override IndexBuffer* createIndexBuffer()
    {
        assert(false, "TODO");
    }

    override void testDrawTriangle()
    {
        setupGLState();
        scope(exit) {restoreGLState();}

        glShadeModel(GL_SMOOTH);
        glBegin(GL_TRIANGLES);

        glColor3f(1.0f, 0.0f, 0.0f);
        glVertex3f(0.0f,  0.0f,  0.0f);
        glColor3f(0.0f, 1.0f, 0.0f);
        glVertex3f(1.0f, 1.0f, 0.0f);
        glColor3f(0.0f, 0.0f, 1.0f);
        glVertex3f(0.0f,  1.0f, 1.0f);

        glEnd();
        // TODO:
        // -Implement createGLSLShader and draw with a shader (and projection matrix)
        // -VBO.
        // -IBO.
        // -Texture.
        // -BlendMode, etc setup/restore
    }

    override void renderFrame(bool delegate(Renderer) drawPartial)
    {
        glClearColor(0, 0, 0, 0);
        glClear(GL_COLOR_BUFFER_BIT);
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

    override Texture* createTexture(const ref Image image)
    {
        //TODO LATER
        assert(false, "TODO");
    }

    override GLSLShader* createGLSLShader()
    {
        assert(false, "TODO");
    }

    override bool isGLSLSupported() const
    {
        return true;
    }

    override @property Vector2u viewportSize() const
    {
        return Vector2u(screenWidth_, screenHeight_);
    }

    override void setBlendMode(const BlendMode blendMode)
    {
        blendMode_ = blendMode;
    }

protected:
    /// Initialize OpenGL context.
    void initGL()
    {
        scope(failure){writeln("OpenGL initialization failed");}
        try
        {
            //Loads the newest available OpenGL version
            glVersion_ = DerelictGL.loadClassicVersions(GLVersion.GL20);

            DerelictGL.loadExtensions();
        }
        catch(DerelictException e)
        {
            throw new RendererInitException
                ("Could not load OpenGL: " ~ e.msg ~
                 "\nPerhaps you need to install new graphics drivers?");
        }

        glClearColor(0.0f, 0.0f, 0.0f, 0.0f);

        const error = glGetError();
        if(error != GL_NO_ERROR)
        {
            writeln("GL error after GL initialization: ", to!string(error));
        }

        glInitialized_ = true;
    }

    /// Swap the front and back buffer. 
    ///
    /// Has to be done by the library that set up GL (e.g. SDL).
    void swapBuffers();

private:
    /// Set up GL state before drawing.
    ///
    /// Allows us to encapsulate GL state, avoiding leaking unexpected state 
    /// between draws.
    void setupGLState()
    {
        glEnable(GL_CULL_FACE);
        glCullFace(GL_BACK);
        final switch(blendMode_)
        {
            case BlendMode.None:
                glDisable(GL_BLEND);
                break;
            case BlendMode.Add:
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

    /// Restore GL state after drawing.
    void restoreGLState()
    {
        glDisable(GL_CULL_FACE);
        glDisable(GL_BLEND);
    }

    /// Set up OpenGL viewport.
    final void setupViewport()
    {
        glViewport(0, 0, screenWidth_, screenHeight_);
    }
}
