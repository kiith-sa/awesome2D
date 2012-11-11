//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Various OpenGL utility functions.
module video.glutils;


import derelict.opengl.gl;

import video.vertexattribute;
import video.primitivetype;


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
GLint glAttributeType(const AttributeType type)
{
    final switch(type)
    {
        case AttributeType.vec2, AttributeType.vec3, AttributeType.vec4:
            return GL_FLOAT;
    }
}