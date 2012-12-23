//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// GL2 (actually, ARB) framebuffer object implementation.
module video.gl2framebuffer;


import std.stdio;
import std.string;
import std.typecons;

import derelict.opengl3.gl;
import gl3n.linalg;

import color;
import image;
import memory.memory;
import video.exceptions;
import video.framebuffer;
import video.glutils;
import video.gl2texture;
import video.texture;


package:

/// Construct a GL2-based framebuffer object backend.
void constructFrameBufferGL2
    (ref FrameBuffer result, const uint width, const uint height,
     ColorFormat format, Flag!"useDepth" useDepth)
{
    string errorMsg;
    if(glErrorOccured(errorMsg))
    {
        writeln("GL error before constructing an FBO: ", errorMsg);
    }

    result.gl2_        = GL2FrameBufferData.init;
    result.dimensions_ = vec2u(width, height);
    result.dtor_       = &dtor;
    result.bind_       = &bind;
    result.release_    = &release;
    result.clear_      = &clear;
    result.toImage_    = &toImage;
    result.texture_    = alloc!Texture;
    scope(failure){free(result.texture_);}

    with(result.gl2_)
    {
        // Create the framebuffer.
        glGenFramebuffers(1, &fbo_);

        scope(failure){glDeleteFramebuffers(1, &fbo_);}
        // If we're constructing while another FBO is bound, we need to rebind
        // it when we're done.
        const previousFBO = bindFrameBuffer(fbo_);
        scope(exit){bindFrameBuffer(previousFBO);}

        if(glErrorOccured(errorMsg))
        {
            writeln("GL error after first binding an FBO: ", errorMsg);
        }

        constructTextureGL2FBO(*(result.texture_), width, height, format);
        const textureHandle = result.texture_.gl2_.textureHandle_;

        if(glErrorOccured(errorMsg))
        {
            writeln("GL error before attaching a texture to an FBO: ", errorMsg);
        }
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                               GL_TEXTURE_2D, textureHandle, 0);

        if(useDepth)
        {
            // The depth buffer
            glGenRenderbuffers(1, &depthRenderBuffer_);
            glBindRenderbuffer(GL_RENDERBUFFER, depthRenderBuffer_);
            glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT, width, height);
            glFramebufferRenderbuffer
                (GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depthRenderBuffer_);
        }
        scope(failure) if(useDepth) {glDeleteRenderbuffers(1, &depthRenderBuffer_);}

        // Specify the buffers we're drawing into.
        const GLenum drawBuffer = GL_COLOR_ATTACHMENT0;
        glDrawBuffers(1, &drawBuffer);

        const status = glCheckFramebufferStatus(GL_FRAMEBUFFER);

        if(glErrorOccured(errorMsg))
        {
            writeln("GL error after creating an FBO: ", errorMsg);
        }

        // Successfully created the FBO.
        if(status == GL_FRAMEBUFFER_COMPLETE)
        {
            return;
        }

        if(status == GL_FRAMEBUFFER_UNSUPPORTED)
        {
            const msg = std.string.format("Unsupported framebuffer format: ", 
                                          width, "x", height, " ", format);
            import std.stdio;
            writeln(msg);
            throw new FrameBufferInitException(msg);
        }
        throw new FrameBufferInitException
            ("Framebuffer initialization error: " ~ to!string(status));
    }
}


/// Data members for the GL2 framebuffer object backend.
struct GL2FrameBufferData
{
    /// GL handle of the framebuffer object.
    GLuint fbo_;
    /// Depth renderbuffer of the FBO.
    GLuint depthRenderBuffer_ = 0;
}


private:

/// Destroy the framebuffer object.
///
/// Implements FrameBuffer::~this.
void dtor(ref FrameBuffer self)
{with(self.gl2_)
{
    string errorMsg;
    if(glErrorOccured(errorMsg))
    {
        writeln("GL error before destroying an FBO: ", errorMsg);
    }
    free(self.texture);
    if(glErrorOccured(errorMsg))
    {
        writeln("GL error after deleting a FBO texture: ", errorMsg);
    }
    if(depthRenderBuffer_ != 0)
    {
        glDeleteRenderbuffers(1, &depthRenderBuffer_);
        if(glErrorOccured(errorMsg))
        {
            writeln("GL error after deleting a FBO depth render buffer: ", errorMsg);
        }
    }
    // No need to unbind the FBO; the FrameBuffer API asserts that the 
    // FBO is not bound when dtor is called.
    // If any FBO is bound here, it's not the one we're deleting.

    // On AMD GPUs (both Catalyst and open source drivers), this causes
    // a GL_INVALID_VALUE; which according to the spec can't happen.
    // No workaround was found, so we just don't delete FBOs.
    //
    // There's still a possibility that this is our bug, not AMD's,
    // though.

    // glDeleteFramebuffers(cast(GLsizei)1, &fbo_);


    if(glErrorOccured(errorMsg))
    {
        writeln("GL error after destroying an FBO: ", errorMsg);
    }
}}

/// Bind the framebuffer object to be drawn to.
///
/// Implements FrameBuffer::bind.
void bind(ref FrameBuffer self)
{with(self.gl2_)
{
    bindFrameBuffer(fbo_);
}}

/// Release the framebuffer object to allow drawing to the screen.
///
/// Implements FrameBuffer::release.
void release(ref FrameBuffer self)
{with(self.gl2_)
{
    bindFrameBuffer(0);
}}

/// Clear any data rendered to the framebuffer.
///
/// Implements FrameBuffer::release.
void clear(ref FrameBuffer self)
{with(self.gl2_)
{
    glClearColor(0, 0, 0, 0);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
}}

/// Copy the contents of the framebuffer to an image.
///
/// Implements FrameBuffer::toImage.
void toImage(ref FrameBuffer self, ref Image image)
{with(self.gl2_)
{
    // If a different texture is currently bound, make sure
    // we rebind it back when done.
    const previousTexture = bindTexture(0, self.texture.gl2_.textureHandle_);
    scope(exit){bindTexture(0, previousTexture);}
    self.texture.bind(0);
    const dim = self.dimensions;
    const colorFormat = ColorFormat.RGBA_8;
    image = Image(dim.x, dim.y, colorFormat);
    glGetTexImage(GL_TEXTURE_2D, 0, glTextureLoadFormat(colorFormat),
                  glTextureType(colorFormat),  image.dataUnsafe.ptr);
    image.flipVertical();
}}


/// Framebuffer object currently bound to GL_FRAMEBUFFER.
GLuint boundFramebuffer_ = 0;

/// Bind specified FBO to GL_FRAMEBUFFER and return the previously bound FBO.
///
/// This should be used instead of glBindFramebuffer to ensure 
/// we can rebind currently bound FBO when constructing a FBO.
GLuint bindFrameBuffer(const GLuint fbo) nothrow
{
    const previous = boundFramebuffer_;
    boundFramebuffer_ = fbo;
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    return previous;
}
