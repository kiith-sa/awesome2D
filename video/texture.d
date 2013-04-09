
//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// 2D texture.
module video.texture;


import color;
import image;
import util.linalg;
import video.gl2texture;

/// Texture filtering modes.
///
/// These specify how the texture is enlarged/shrunk as the viewer 
/// gets closer/farther.
enum TextureFiltering
{
    /// Nearest-neighbor (blocky, like in old 1990's 3D games).
    Nearest,
    /// Bilinear.
    Linear
}

/// Texture wrapping modes.
///
/// These specify how the texture is applied outside its area 
/// (i.e. outside the (0,0, 1,1) texture coord rectangle.)
enum TextureWrap
{
    /// Texture is repeated infinitely.
    Repeat,
    /// Colors at the edge of the texture are used.
    ClampToEdge
}

/// A convenience builder struct to pass texture parameters with.
struct TextureParams
{
    /// Texture filtering mode.
    TextureFiltering filtering_  = TextureFiltering.Linear;
    /// Texture wrapping mode.
    TextureWrap wrap_            = TextureWrap.Repeat;

    /// True if the GPU format is overridden.
    bool gpuFormatOverridden_      = false;

    /// Used to override on-GPU format. 
    /// Allows to create RGB5 textures from RGB8 images .
    ColorFormat gpuFormatOverride_;

    /// Set texture filtering mode.
    ref TextureParams filtering(const TextureFiltering filtering) @safe pure nothrow
    {
        filtering_ = filtering;
        return this;
    }

    /// Set texture wrapping mode.
    ref TextureParams wrap(const TextureWrap wrap) @safe pure nothrow
    {
        wrap_ = wrap;
        return this;
    }

    /// Override on-GPU texture color format. 
    /// Allows to create RGB5 textures from RGB8 images .
    ///
    /// Note that this might still be different from the final on-GPU format 
    /// if the GPU or Renderer implementation doesn't support the format.
    ref TextureParams overrideGPUFormat(const ColorFormat format) @safe pure nothrow
    {
        gpuFormatOverride_  = format;
        gpuFormatOverridden_ = true;
        return this;
    }
}

/// 2D texture.
///
/// Constructed by Renderer.createTexture().
struct Texture
{
package:
    union 
    {
        // Data members for the GL2 backend.
        GL2TextureData gl2_;
    }

    // X and Y size of the texture in pixels.
    vec2u dimensions_;

    // Color format of the texture.
    ColorFormat format_;

    // Parameters the texture was constructed with (filtering, wrapping, etc.).
    TextureParams params_;
    // Alias for readability.
    alias Texture Self;

    // Pointer to the destructor implementation.
    void function(ref Self) @trusted nothrow dtor_;
    // Pointer to the bind implementation.
    void function(ref Self, const uint) @trusted nothrow bind_;
    // Pointer to the setPixels_ implementation.
    void function(ref Self, const vec2u, ref const Image) @trusted nothrow setPixels_;

public:
    /// Destroy the Texture, freeing any resources used.
    @safe nothrow ~this()
    {
        dtor_(this);
    }

    /// Get the dimensions of the texture in pixels.
    @property vec2u dimensions() @safe const pure nothrow {return dimensions_;}

    /// Get the color format of the texture.
    @property ColorFormat format() @safe const pure nothrow {return format_;}

    /// Bind the texture to specified texture unit (to be used for drawing).
    ///
    /// If textureUnit is greater than the maximum texture unit
    /// supported on the machine, it will be silently ignored.
    /// You can determine the number of texture units supported by
    /// calling Renderer.textureUnitCount. It must always be at least 2.
    ///
    /// Textures are never "unbound" or "released"; a different texture 
    /// can be bound to a unit, overriding the previous binding.
    void bind(const uint textureUnit) @safe nothrow
    {
        bind_(this, textureUnit);
    }

    /// Get the lower bound of number of bytes taken by this struct in RAM (not VRAM).
    @property size_t memoryBytes() @safe const pure nothrow 
    {
        return this.sizeof;
    }

    /// Overwrite pixels in an area of the texture by specified image.
    ///
    /// Params:  offset = The bottom-left corner of the area to overwrite.
    ///          image  = Image to copy pixels from. Must be in the same format
    ///                   as the image used to create the texture.
    ///                   The image must not extend outside texture dimensions.
    void setPixels(const vec2u offset, ref const Image image) @safe nothrow
    {
        const totalExtents = offset + image.size;
        assert(totalExtents.x <= dimensions_.x && totalExtents.y <= dimensions_.y,
               "Trying to set pixels outside of texture (offset or image too large)");
        assert(image.format == format_,
               "Trying to set pixels from an image with different color format");
        setPixels_(this, offset, image);
    }
}


