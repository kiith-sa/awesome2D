//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// GL2 2D texture backend.
module video.gl2texture;


import std.conv;
import std.stdio;

import derelict.opengl3.gl;

import color;
import image;
import util.linalg;
import video.exceptions;
import video.glutils;
import video.texture;


package:

/// Construct a GL2 texture backend with specified parameters from specified image.
void constructTextureGL2
    (ref Texture texture, ref const Image image, const ref TextureParams params)
{
    texture.gl2_        = GL2TextureData.init;
    texture.dimensions_ = image.size();
    texture.format_     = image.format;
    texture.params_     = params;
    texture.dtor_       = &dtor;
    texture.bind_       = &bind;
    texture.setPixels_  = &setPixels;

    with(texture)
    {
        const colorFormat = image.format;

        if(!glTextureSizeSupported(dimensions_, image.format))
        {
            const msg = "Texture size/format combination not supported: " ~
                        to!string(dimensions_) ~ ", " ~ to!string(colorFormat);
            throw new TextureInitException(msg);
        }

        glGenTextures(1, &gl2_.textureHandle_);
        // If we're constructing a texture while another texture is bound,
        // make sure we rebind it.
        const previous = bindTexture(0, gl2_.textureHandle_);
        scope(exit) {bindTexture(0, previous);}

        // Set texture parameters.
        const glFiltering = params_.filtering_.glTextureFiltering();
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, glFiltering);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, glFiltering);
        const glWrap = params_.wrap_.glTextureWrap();
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, glWrap);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, glWrap);

        // Texture loading parameters.
        const internalFormat = params_.gpuFormatOverridden_ 
                             ? params_.gpuFormatOverride_.glTextureInternalFormat()
                             : colorFormat.glTextureInternalFormat();
        const loadFormat     = colorFormat.glTextureLoadFormat();
        const type           = colorFormat.glTextureType();

        string errorMsg;
        if(glErrorOccured(errorMsg))
        {
            writeln("GL error before loading a texture: ", errorMsg);
        }

        // Load the texture.
        glTexImage2D(GL_TEXTURE_2D, 0, internalFormat,
                     dimensions_.x, dimensions_.y, 0,
                     loadFormat, type, cast(void*)image.data.ptr);

        if(glErrorOccured(errorMsg))
        {
            writeln("GL error after loading a texture: ", errorMsg);
        }
    }
}

/// Construct a GL2 texture to be used in a framebuffer object.
///
/// Params:  texture = Texture instance to initialize.
///          width   = Width of the texture/FBO in pixels.
///          height  = Width of the texture/FBO in pixels.
///          format  = Color format of the texture/FBO.
///
/// Throws:  FrameBufferInitException on failure.
void constructTextureGL2FBO
    (ref Texture texture, const uint width, const uint height, const ColorFormat format)
{
    texture.gl2_        = GL2TextureData.init;
    texture.dimensions_ = vec2u(width, height);
    texture.params_     = TextureParams().filtering(TextureFiltering.Nearest);
    texture.format_     = format;
    texture.dtor_       = &dtor;
    texture.bind_       = &bind;

    if(!glTextureSizeSupported(texture.dimensions_, format))
    {
        const msg = "FBO texture size/format combination not supported: " ~
                    to!string(texture.dimensions_) ~ ", " ~ to!string(texture.format_);
        throw new FrameBufferInitException(msg);
    }

    glGenTextures(1, &texture.gl2_.textureHandle_);
    // If we're constructing a texture while another texture is bound,
    // make sure we rebind it.
    const previous = bindTexture(0, texture.gl2_.textureHandle_);
    scope(exit) {bindTexture(0, previous);}

    // Set texture parameters.
    const glFiltering = texture.params_.filtering_.glTextureFiltering();
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, glFiltering);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, glFiltering);
    const glWrap = texture.params_.wrap_.glTextureWrap();
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, glWrap);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, glWrap);

    // Texture loading parameters.
    const internalFormat = texture.format_.glTextureInternalFormat();
    const loadFormat     = texture.format_.glTextureLoadFormat();
    const type           = texture.format_.glTextureType();

    string errorMsg;
    if(glErrorOccured(errorMsg))
    {
        writeln("GL error before creating a FBO texture: ", errorMsg);
    }

    // Create an empty texture (the null data pointer).
    glTexImage2D(GL_TEXTURE_2D, 0, internalFormat,
                 texture.dimensions_.x, texture.dimensions_.y, 0,
                 loadFormat, type, cast(void*) null);

    if(glErrorOccured(errorMsg))
    {
        writeln("GL error after creating a FBO texture: ", errorMsg);
    }
}

/// Data members of the GL2 texture backend.
struct GL2TextureData
{
    /// OpenGL handle to the texture.
    GLuint textureHandle_;
}

/// Bind a texture to specified texture unit.
///
/// Params:  textureUnit = Texture unit to bind to.
///          texture     = GL handle of the texture to bind.
///
/// Returns: Handle of the texture previously bound to this unit.
///
/// This should be used instead of glBindTexture to ensure we 
/// rebind the last texture we called bind() method of after 
/// doing operations that need us to bind a different texture to the unit.
GLuint bindTexture(const uint textureUnit, const GLuint texture) @trusted nothrow
{
    glActiveTexture(GL_TEXTURE0 + textureUnit);
    glBindTexture(GL_TEXTURE_2D, texture);
    const previous = boundTextures_[textureUnit];
    boundTextures_[textureUnit] = texture;
    return previous;
}

private:

/// boundTextures_[x] is the handle of the texture bound to that texture unit (if any);
GLuint[32] boundTextures_;

/// Destroy the texture.
///
/// Implements Texture::~this.
void dtor(ref Texture self) @trusted nothrow
{with(self.gl2_)
{
    // Not initialized.
    // (might be called when an exception is thrown before completing initialization)
    if(textureHandle_ == 0)
    {
        return;
    }
    // Make sure the texture is not bound to any unit.
    foreach(uint unit, ref texture; boundTextures_) if(texture == textureHandle_)
    {
        bindTexture(unit, 0u);
        texture = 0;
    }
    glDeleteTextures(1, &textureHandle_);
}}

/// Bind the texture to specified unit.
///
/// Implements Texture::bind.
void bind(ref Texture self, const uint textureUnit) @safe nothrow
{with(self.gl2_)
{
    bindTexture(textureUnit, textureHandle_);
}}

/// Set pixels in specified area to pixels from specified image.
///
/// Implements Texture::setPixels.
void setPixels(ref Texture self, const vec2u offset, ref const Image image) @trusted nothrow
{with(self.gl2_)
{
    // Texture.setPixels() ensures the image format matches the texture and that 
    // it doesn't extend outside of the texture.

    // Texture loading parameters.
    const loadFormat = self.format_.glTextureLoadFormat();
    const type       = self.format_.glTextureType();

    // Bind to texture unit 0 while we work, then rebind the previously bound texture.
    const previousTexture = bindTexture(0, textureHandle_);
    scope(exit){bindTexture(0, previousTexture);}

    // By default, GL aligns rows to 4 byte boundaries, which messes up less than
    // 32bpp images (e.g. RGB_8, grayscale) when their row sizes are not
    // divisible by 4. So we force alignment here.
    glPixelStorei(GL_UNPACK_ALIGNMENT, packAlignment(image.format));
    // Write to texture
    glTexSubImage2D(GL_TEXTURE_2D, 0, offset.x, offset.y, 
                    image.size.x, image.size.y,
                    loadFormat, type, image.data.ptr);
}}
