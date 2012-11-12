//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// GL2 2D texture backend.
module video.gl2texture;


import std.conv;
import std.stdio;

import derelict.opengl.gl;
import image;
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
    texture.params_     = params;
    texture.dtor_       = &dtor;
    texture.bind_       = &bind;

    with(texture)
    {
        const colorFormat = image.format;

        if(!glTextureSizeSupported(dimensions_, image.format))
        {
            const msg = "Texture size/format combination not supported: " ~
                        to!string(dimensions_) ~ ", " ~ to!string(colorFormat);
            throw new TextureInitException(msg);
        }

        glActiveTexture(GL_TEXTURE0);
        glGenTextures(1, &gl2_.textureHandle_);
        glBindTexture(GL_TEXTURE_2D, gl2_.textureHandle_);

        // Set texture parameters.
        const glFiltering = params_.filtering_.glTextureFiltering();
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, glFiltering);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, glFiltering);
        const glWrap = params_.wrap_.glTextureWrap();
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, glWrap);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, glWrap);

        // Texture loading parameters.
        const internalFormat = colorFormat.glTextureInternalFormat();
        const loadFormat     = colorFormat.glTextureLoadFormat();
        const type           = colorFormat.glTextureType();

        auto error = glGetError();
        if(error != GL_NO_ERROR)
        {
            writeln("GL error before loading a texture: ", to!string(error));
        }

        // Load the texture.
        glTexImage2D(GL_TEXTURE_2D, 0, internalFormat,
                     dimensions_.x, dimensions_.y, 0,
                     loadFormat, type, cast(void*)image.data.ptr);

        error = glGetError();
        if(error != GL_NO_ERROR)
        {
            writeln("GL error after loading a texture: ", to!string(error));
        }
    }
}

/// Data members of the GL2 texture backend.
struct GL2TextureData
{
    /// OpenGL handle to the texture.
    GLuint textureHandle_;
}


private:

/// boundTextures_[x] is the handle of the texture bound to that texture unit (if any);
GLuint[256] boundTextures_;

/// Destroy the texture.
///
/// Implements Texture::~this.
void dtor(ref Texture self)
{with(self.gl2_)
{
    // Not initialized.
    // (might be called when an exception is thrown before completing initialization)
    if(textureHandle_ == 0)
    {
        return;
    }
    // Make sure the texture is not bound to any unit.
    foreach(unit, ref texture; boundTextures_)
    {
        glBindTexture(GL_TEXTURE0 + cast(uint)unit, 0);
        texture = 0;
    }
    glDeleteTextures(1, &textureHandle_);
}}

/// Bind the texture to specified unit.
///
/// Implements Texture::bind.
void bind(ref Texture self, const uint textureUnit)
{with(self.gl2_)
{
    glActiveTexture(GL_TEXTURE0 + textureUnit);
    glBindTexture(GL_TEXTURE_2D, textureHandle_);
    boundTextures_[textureUnit] = textureHandle_;
}}
