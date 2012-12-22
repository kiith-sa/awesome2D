//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Framebuffer object API.
module video.framebuffer;


import gl3n.linalg;

import image;
import video.gl2framebuffer;
import video.texture;


/// Framebuffer object API.
///
/// Can be used to render to textures, various postprocessing, etc.
struct FrameBuffer
{
package:
    union
    {
        // Data members for the GL2 backend.
        GL2FrameBufferData gl2_;
    }

    // X and Y size of the framebuffer in pixels.
    vec2u dimensions_;

    // Is the framebuffer object bound for drawing?
    bool bound_;

    // Texture of this framebuffer object.
    Texture* texture_;

    // Is any framebuffer object bound?
    static bool isAFrameBufferBound_;

    // Alias for readability.
    alias FrameBuffer Self;

    // Pointer to the destructor implementation.
    void function(ref Self)            dtor_;
    // Pointer to the bind implementation.
    void function(ref Self)            bind_;
    // Pointer to the release implementation.
    void function(ref Self)            release_;
    // Pointer to the clear implementation.
    void function(ref Self)            clear_;
    // Pointer to the toImage implementation.
    void function(ref Self, ref Image) toImage_;

public:
    /// Destroy the framebuffer, freeing any resources.
    ///
    /// The framebuffer must not be bound when this is called.
    ///
    /// This also destroys the framebuffer's internal texture (that might have 
    /// been accessed through the texture() property).
    ~this()
    {
        assert(!bound_, "Trying to destroy a bound FBO");
        dtor_(this);
    }

    /// Get the dimensions of the framebuffer in pixels.
    @property vec2u dimensions() @safe const pure nothrow {return dimensions_;}

    /// Bind the framebuffer for drawing.
    ///
    /// Only one framebuffer object can be bound at a time.
    ///
    /// Any drawing operations after bind() will draw to the frame buffer.
    void bind()
    {
        assert(!isAFrameBufferBound_, 
               "Trying to bind a framebuffer object before releasing the previous one");
        bound_ = true;
        isAFrameBufferBound_ = true;
        bind_(this);
    }

    /// Release the framebuffer. 
    ///
    /// Drawing operations after releasing the buffer will draw to the default
    /// framebuffer (screen).
    void release()
    {
        release_(this);
        bound_ = false;
        isAFrameBufferBound_ = false;
    }

    /// Clears data rendered into the framebuffer, making the entire framebuffer black.
    ///
    /// If depth buffer is used, it will be cleared as well.
    ///
    /// The FBO must be bound when this is called.
    void clear()
    {
        assert(bound_, "Trying to clear a FrameBuffer that is not bound.");
        clear_(this);
    }

    /// Return a pointer to the framebuffer's texture.
    ///
    /// Can only be called when the framebuffer is not bound.
    ///
    /// The texture is owned by the framebuffer; it must not be deleted
    /// by the caller.
    @property Texture* texture()
    {
        assert(!bound_, "Trying to get the texture of a bound framebuffer object");
        return texture_;
    }

    /// Copy the framebuffer to an image.
    ///
    /// Contents of the passed image will be completely replaced by the 
    /// data from framebuffer.
    void toImage(ref Image image)
    {
        toImage_(this, image);
    }
}
