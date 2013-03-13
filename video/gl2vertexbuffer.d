//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// GL2 vertex buffer implementation.
module video.gl2vertexbuffer;


import core.stdc.string;

import derelict.opengl3.gl;
import gl3n.linalg;

import color;
import memory.memory;
import video.exceptions;
import video.gl2bufferobject;
import video.gl2bufferobject;
import video.gl2glslshader;
import video.gl2indexbuffer;
import video.glslshader;
import video.glutils;
import video.indexbuffer;
import video.limits;
import video.primitivetype;
import video.vertexattribute;
import video.vertexbuffer;


package:

/// Construct a GL2-based vertex buffer backend.
void constructVertexBufferBackendGL2
    (ref VertexBufferBackend backend, ref const VertexAttributeSpec attributeSpec) 
{
    backend.gl2_       = GL2VertexBufferBackendData.init;
    backend.gl2_.initialize(attributeSpec);
    backend.dtor_      = &dtor;
    backend.lock_      = &lock;
    backend.unlock_    = &unlock;
    backend.addVertex_ = &addVertex;
    backend.bind_      = &bind;
    backend.release_   = &release;
}


/// Data members of the GL2 vertex buffer backend.
struct GL2VertexBufferBackendData
{
    /// Pointer to the specification of vertex attributes in this buffer.
    const(VertexAttributeSpec)* attributeSpec_;

    /// Size of a signle vertex in bytes.
    size_t  vertexBytes_;
    /// Number of vertices that can be held in verticesRAM_.
    size_t  vertexCapacity_;
    /// Copy of the vertex buffer in RAM.
    /// 
    /// Used for modifications; uploaded to the VBO when lock() is called.
    ubyte[] verticesRAM_;
    /// VBO with the vertex data.
    GL2BufferObject verticesVBO_;

    /// Initialize GL2VertexBufferBackendData with specified vertex attribute spec.
    void initialize(ref const VertexAttributeSpec attributeSpec)
    {
        attributeSpec_  = &attributeSpec;
        verticesVBO_    = GL2BufferObject(GL_ARRAY_BUFFER);
        vertexBytes_    = 0;
        // Preallocate space for 16 vertices.
        vertexCapacity_ = 16;
        foreach(attrib; (*attributeSpec_).attributes)
        {
            vertexBytes_ += attrib.type.attributeSize();
        }
        verticesRAM_ = allocArray!ubyte(vertexCapacity_ * vertexBytes_);
    }

    /// Deinitialize, freeing all used resources.
    void deinitialize()
    {
        free(verticesRAM_);
        clear(verticesVBO_);
    }
}

/// Draw the vertex buffer.
///
/// Params:  self        = Vertex buffer to draw (must be GL2).
///          indexBuffer = If not null, specifies indices of vertices to draw.
///                        Otherwise, all vertices in the buffer are drawn in
///                        consecutive order.
///          shader      = Shader program used for drawing.
///          first       = Index of the first vertex of vertexBuffer to use
///                        if indexBuffer is null, or the first index of
///                        indexBuffer to use otherwise.
///          elements    = Number of vertices to draw.
void drawVertexBufferGL2
    (ref VertexBufferBackend self, IndexBuffer* indexBuffer,
     ref GLSLShaderProgram shaderProgram, const uint first, const uint elements)
{with(self) with(gl2_)
{
    assert(locked_, "Trying to draw a vertex buffer that is not locked");

    // Stores enabled vertex attributes so we can disable them when done.
    GLint[MAX_ATTRIBUTES] enabledAttributes;
    size_t totalAttributes = 0;
    // Offset of the current attribute relative to start of a vertex in the VBO.
    size_t attributeOffset = 0;

    scope(exit)
    {
        foreach(attribArray; enabledAttributes[0 .. totalAttributes])
        {
            glDisableVertexAttribArray(attribArray);
        }
    }
    // Enable all used vertex attributes.
    foreach(attribute; (*attributeSpec_).attributes)
    {
        const name = attributeInterpretationNames[attribute.interpretation];
        const outerHandle = shaderProgram.getAttributeOuterHandle(name);

        // GL handle to the attribute.
        GLint handle;
        try
        {
            handle = shaderProgram.getAttributeGLHandle(outerHandle);
        }
        catch(GLSLAttributeException e)
        {
            // Ignore missing attributes
            attributeOffset += attribute.type.attributeSize();
            ++totalAttributes;
            continue;
        }
        enabledAttributes[totalAttributes] = handle;
        glVertexAttribPointer(handle, cast(int)attribute.type.attributeDimensions(), 
                              attribute.type.glAttributeType(), GL_FALSE, 
                              cast(int)vertexBytes_, cast(const(void*))attributeOffset);
        glEnableVertexAttribArray(handle);

        // TODO (low-priority) 
        // cache the outer handles 
        // to default attributes in the shader program itself.

        attributeOffset += attribute.type.attributeSize();
        ++totalAttributes;
    }

    final switch(primitiveType_)
    {
        case PrimitiveType.Triangles:
            assert(elements % 3 == 0, 
                   "Number of vertices drawn must be divisible by 3 when drawing triangles");
            break;
        case PrimitiveType.Lines:
            assert(elements % 2 == 0, 
                   "Number of vertices drawn must be divisible by 2 when drawing lines");
            break;
    }

    // Draw.
    if(indexBuffer !is null)
    {
        glDrawElements(primitiveType_.glPrimitiveType(), elements,
                       GL_UNSIGNED_INT, cast(GLvoid*)null + first * GLuint.sizeof);
    }
    else
    {
        glDrawArrays(primitiveType_.glPrimitiveType(), first, elements);
    }
}}



private:

/// Destroy the vertex buffer.
///
/// Implements VertexBuffer::~this.
void dtor(ref VertexBufferBackend self)
{with(self.gl2_)
{
    deinitialize();
}}

/// Lock the vertex buffer so it can be bound.
///
/// Implements VertexBuffer::lock.
void lock(ref VertexBufferBackend self)
{with(self) with(gl2_)
{
    verticesVBO_.uploadData(cast(void*)verticesRAM_, vertexCount_ * vertexBytes_);
}}

/// Unlock the vertex buffer so it can be modified.
///
/// Implements VertexBuffer::unlock.
void unlock(ref VertexBufferBackend self) {}

/// Bind the vertex buffer so it can be drawn.
///
/// Implements VertexBuffer::bind.
void bind(ref VertexBufferBackend self)
{with(self) with(gl2_)
{
    verticesVBO_.bind();
}}

/// Release the vertex buffer after drawing.
///
/// Implements VertexBuffer::release.
void release(ref VertexBufferBackend self) 
{with(self) with(gl2_)
{
    verticesVBO_.release();
}}

/// Add a new vertex to the vertex buffer.
///
/// Implements VertexBuffer::addVertex.
void addVertex(ref VertexBufferBackend self, const void* vertexInPtr)
{with(self) with(gl2_)
{
    assert(vertexCount_ <= vertexCapacity_,
           "There are more vertices than allocated space");
    // Out of space - reallocate.
    if(vertexCount_ == vertexCapacity_)
    {
        vertexCapacity_ *= 2;
        verticesRAM_ = realloc(verticesRAM_, vertexCapacity_ * vertexBytes_);
    }

    // Add the vertex.
    memcpy(verticesRAM_.ptr + vertexCount_ * vertexBytes_, vertexInPtr, vertexBytes_);
    // Frontend increments vertexCount_.
}}

