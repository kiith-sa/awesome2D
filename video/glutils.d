//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Various OpenGL utility functions.
module video.glutils;


import std.algorithm;
import std.array;

import derelict.opengl3.gl;

import color;
import util.linalg;
import video.primitivetype;
import video.texture;
import video.vertexattribute;


/// Translate PrimitiveType to OpenGL primitive type.
GLint glPrimitiveType(const PrimitiveType primitiveType) @safe pure nothrow
{
    final switch(primitiveType)
    {
        case PrimitiveType.Triangles: return GL_TRIANGLES;
        case PrimitiveType.Lines:     return GL_LINES;
    }
}

/// Get OpenGL data type of a component of an attribute with specified attribute type.
///
/// E.g. vec3 is a vector of 3 floats, so GL data type of AttributeType.vec3 is GL_FLOAT.
GLint glAttributeType(const AttributeType type) @safe pure nothrow
{
    final switch(type)
    {
        case AttributeType.vec2, AttributeType.vec3, AttributeType.vec4:
            return GL_FLOAT;
    }
}

/// Translate TextureFiltering to OpenGL texture filtering mode.
GLint glTextureFiltering(const TextureFiltering filter) @safe pure nothrow
{
    final switch(filter)
    {
        case TextureFiltering.Nearest: return GL_NEAREST;
        case TextureFiltering.Linear:  return GL_LINEAR;
    }
}

/// Translate TextureWrap to OpenGL texture wrap mode.
GLint glTextureWrap(const TextureWrap wrap) @safe pure nothrow
{
    final switch(wrap)
    {
        case TextureWrap.Repeat:      return GL_REPEAT;
        case TextureWrap.ClampToEdge: return GL_CLAMP_TO_EDGE;
    }
}

/// Get internal (on-GPU) GL pixel format (internalFormat passed to glTexImage2D())
/// corresponding to a ColorFormat.
GLint glTextureInternalFormat(const ColorFormat format) @safe pure nothrow
{
    final switch(format) with(ColorFormat)
    {
        case RGB_565:   return GL_RGB5;
        case RGB_5:     return GL_RGB5;
        case RGBA_5551: return GL_RGB5_A1;
        case RGBA_4:    return GL_RGBA4;
        case RGB_8:     return GL_RGB8;
        case RGBA_8:    return GL_RGBA8;
        case GRAY_8:    return GL_RED;
    }
}

/// Get a GL enum representing the format of pixel data to be loaded to a GL texture.
GLenum glTextureLoadFormat(const ColorFormat format) @safe pure nothrow
{
    final switch(format) with(ColorFormat)
    {
        case RGB_565:   return GL_RGB;
        case RGB_5:     return GL_RGB;
        case RGBA_5551: return GL_RGBA;
        case RGBA_4:    return GL_RGBA;
        case RGB_8:     return GL_RGB;
        case RGBA_8:    return GL_RGBA;
        case GRAY_8:    return GL_RED;
    }
}

/// Get a GL enum representing the data type of pixel data to be loaded to a GL texture.
GLenum glTextureType(const ColorFormat format) @safe pure nothrow
{
    final switch(format) with(ColorFormat)
    {
        case RGB_565:   return GL_UNSIGNED_SHORT_5_6_5;
        case RGB_5:     return GL_UNSIGNED_SHORT_5_5_5_1;
        case RGBA_5551: return GL_UNSIGNED_SHORT_5_5_5_1;
        case RGBA_4:    return GL_UNSIGNED_SHORT_4_4_4_4;
        case RGB_8:     return GL_UNSIGNED_BYTE;
        case RGBA_8:    return GL_UNSIGNED_BYTE;
        case GRAY_8:    return GL_UNSIGNED_BYTE;
    }
}

/// Determine OpenGL packing/unpacking alignment needed for specified color format.
/// 
/// GL only supports pixels to be aligned to 1, 2, 4 and 8 byte boundaries so using
/// bytes per pixel doesn't work for e.g. RGB8.
/// 
/// Params:  format = Format to get alignment for.
/// 
/// Returns: Alignment for specified format.
static GLint packAlignment(const ColorFormat format) @safe pure nothrow
{
    final switch(format) with(ColorFormat)
    {
        case RGB_565, RGB_5, RGBA_5551, RGBA_4: return 2;
        case RGB_8:                             return 1;
        case RGBA_8:                            return 4;
        case GRAY_8:                            return 1;
    }
}

/// Determine if specified texture size/format combination is supported.
bool glTextureSizeSupported(const vec2u size, const ColorFormat format) @system nothrow
{
    const internalFormat = format.glTextureInternalFormat();
    const loadFormat     = format.glTextureLoadFormat();
    const type           = format.glTextureType();

    // Try creating a texture proxy with these parameters.
    // If the result has zero dimensions, this format is not supported.
    glTexImage2D(GL_PROXY_TEXTURE_2D, 0, internalFormat, size.x, size.y, 0,
                 loadFormat, type, null);

    GLint width  = size.x;
    GLint height = size.y;
    glGetTexLevelParameteriv(GL_PROXY_TEXTURE_2D, 0, GL_TEXTURE_WIDTH, &width);
    glGetTexLevelParameteriv(GL_PROXY_TEXTURE_2D, 0, GL_TEXTURE_WIDTH, &height);

    return width != 0 && height != 0;
}

/// Determine if specified OpenGL extension is supported.
bool glIsExtensionAvailable(const string name) @system
{
    auto extstr = to!string(glGetString(GL_EXTENSIONS));
    return extstr.split(" ").canFind(name);
}

/// Has a GL error occured?
///
/// Returns true if a GL error has occured since the last call to glErrorOccured
/// or glGetError. If an error occurs, msg is set to the name of the error.
bool glErrorOccured(ref string msg) @system nothrow
{
    glFinish();
    const error = glGetError();
    if(error == GL_NO_ERROR){return false;}
    switch(error)
    {
        case GL_NO_ERROR:                      msg = "GL_NO_ERROR";                      break;
        case GL_INVALID_ENUM:                  msg = "GL_INVALID_ENUM";                  break;
        case GL_INVALID_VALUE:                 msg = "GL_INVALID_VALUE";                 break;
        case GL_INVALID_OPERATION:             msg = "GL_INVALID_OPERATION";             break;
        case GL_INVALID_FRAMEBUFFER_OPERATION: msg = "GL_INVALID_FRAMEBUFFER_OPERATION"; break;
        case GL_OUT_OF_MEMORY:                 msg = "GL_OUT_OF_MEMORY";                 break;
        default:                               msg = "UNKNOWN_GL_ERROR";                 break;
    }
    return true;
}
