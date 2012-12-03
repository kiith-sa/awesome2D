//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// GL2 (actually, ARB) framebuffer object implementation.
module video.gl2framebuffer;


import std.typecons;

import gl3n.linalg;
import derelict.opengl3.gl;

import color;
import image;
import video.framebuffer;
import video.texture;


package:

/// Construct a GL2-based framebuffer object backend.
void constructFrameBufferGL2
    (ref FrameBuffer result, const uint width, const uint height,
     ColorFormat format, Flag!"useDepth" useDepth)
{
    result.gl2_        = GL2FrameBufferData.init;
    result.dimensions_ = vec2u(width, height);
    result.dtor_       = &dtor;
    result.bind_       = &bind;
    result.release_    = &release;
    result.texture_    = &texture;
    result.toImage_    = &toImage;
    //TODO initialize framebuffer data,
    //handle, etc.
}


/// Data members for the GL2 framebuffer object backend.
struct GL2FrameBufferData
{
    GLuint fbo_;
    //TODO
}


private:

/// Destroy the framebuffer object.
///
/// Implements FrameBuffer::~this.
void dtor(ref FrameBuffer self)
{with(self.gl2_)
{
    glDeleteFramebuffers(1, &fbo_);
    assert(false, "TODO (delete texture, renderbuffer)");
}}

/// Bind the framebuffer object to be drawn to.
///
/// Implements FrameBuffer::bind.
void bind(ref FrameBuffer self)
{with(self.gl2_)
{
    glBindFramebuffer(GL_FRAMEBUFFER, fbo_);
}}

/// Release the framebuffer object to allow drawing to the screen.
///
/// Implements FrameBuffer::release.
void release(ref FrameBuffer self)
{with(self.gl2_)
{
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
}}

/// Return a pointer to the internal texture of the framebuffer.
///
/// Implements FrameBuffer::texture.
Texture* texture(ref FrameBuffer self)
{with(self.gl2_)
{
    assert(false, "TODO");
}}

/// Copy the contents of the framebuffer to an image.
///
/// Implements FrameBuffer::toImage.
void toImage(ref FrameBuffer self, ref Image image)
{with(self.gl2_)
{
    assert(false, "TODO");
}}
