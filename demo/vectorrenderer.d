//          Copyright Ferdinand Majerech 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


// Handles vector drawing functionality.
module demo.vectorrenderer;


import std.algorithm;

import dgamevfs._;

import color;
import containers.vector; 
alias containers.vector.Vector Vector;
import demo.camera2d;
import demo.spriterenderer;
import demo.spritetype;
import memory.memory;
import util.linalg;
import video.renderer;
import video.uniform;
import video.vertexbuffer;

/// Vector graphics sprite.
///
/// Consists of one or more lines and/or triangles. Created, managed and drawn by
/// VectorRenerer.
struct VectorSprite
{
private:
    // VectorRenderer that has created this sprite.
    VectorRenderer vectorRenderer_;
    // Is this sprite locked (i.e; immutable, ready for drawing)?
    bool locked_ = false;
    // Vertices of lines in the sprite.
    //
    // Pairs (0-1, 2-3, etc.) form lines.
    Vector!VectorVertex lineVertices_;
    // Index to the VectorRenderer's vertex buffer where the lines of this sprite begin.
    //
    // uint.max means the vertices have not yet been uploaded to the vertex buffer.
    uint lineVBufferOffset_ = uint.max;
    // Vertices of triangles in the sprite.
    //
    // Triplets (0-1-2, 3-4-5, etc.) form triangles.
    Vector!VectorVertex triVertices_;
    // Index to the VectorRenderer's vertex buffer where the triangles of this sprite begin.
    //
    // uint.max means the vertices have not yet been uploaded to the vertex buffer.
    uint triVBufferOffset_ = uint.max;

public:
    @disable this();

    // Construct a vector sprite.
    //
    // Can only be called by VectorRenderer (public to allow emplace to call this).
    this(VectorRenderer renderer)
    {
        vectorRenderer_ = renderer;
    }

    /// Destroy the vector sprite.
    ~this()
    {
        vectorRenderer_.vectorSpriteDeleted(&this);
    }

    /// Lock the sprite, disallowing modifications.
    ///
    /// Must be called before drawing.
    /// The vector sprite can not be modified, or unlocked, once locked.
    void lock() @safe pure nothrow
    {
        assert(lineVertices_.length % 2 == 0, 
               "Uneven number of line vertices in a VectorSprite");
        assert(triVertices_.length % 3 == 0, 
               "Number of triangle vertices in a VectorSprite not divisible by 3");
        locked_ = true;
    }

    /// Add a line to the vector sprite.
    ///
    /// Must not be called once the sprite is locked.
    ///
    /// Params:  start      = Position of the line start.
    ///          startColor = Color of the line start.
    ///          end        = Position of the line end.
    ///          endColor   = Color of the line end.
    void addLine(const vec2 start, const Color startColor,
                 const vec2 end, const Color endColor) @safe
    {
        assert(!locked_, "Trying to add a line to a locked VectorSprite");
        lineVertices_ ~= VectorVertex(start, startColor.toVec4());
        lineVertices_ ~= VectorVertex(end,   endColor.toVec4());
    }

    /// Add a triangle to the vector sprite.
    ///
    /// Must not be called once the sprite is locked.
    ///
    /// Params:  a      = Position of the first triangle vertex.
    ///          aColor = Color of the first triangle vertex.
    ///          b      = Position of the second triangle vertex.
    ///          bColor = Color of the second triangle vertex.
    ///          b      = Position of the third triangle vertex.
    ///          cColor = Color of the third triangle vertex.
    void addTriangle(const vec2 a, const Color aColor,
                     const vec2 b, const Color bColor,
                     const vec2 c, const Color cColor) @safe
    {
        assert(!locked_, "Trying to add a triangle to a locked VectorSprite");
        triVertices_ ~= VectorVertex(a, aColor.toVec4());
        triVertices_ ~= VectorVertex(b, bColor.toVec4());
        triVertices_ ~= VectorVertex(c, cColor.toVec4());
    }

    /// Is this vector sprite locked (i.e; finalized, ready for drawing)?
    @property bool locked() @safe const pure nothrow {return locked_;}

    /// Are there any lines in this vector sprite?
    @property bool hasLines() @safe const pure nothrow {return lineVertices_.length > 0;}

    /// Are there any triangles in this vector sprite?
    @property bool hasTris() @safe const pure nothrow {return triVertices_.length > 0;}
}

/// Creates, manages and draws vector sprites.
class VectorRenderer : SpriteUnlitRenderer
{
private:
    /// Vector sprites created by this renderer.
    Vector!(VectorSprite*) sprites_;

    /// Currently bound vertex buffer (only relevant when drawing).
    VertexBuffer!VectorVertex* boundVBuffer_ = null;

    /// Vertex buffer storing vertices of lines in sprites.
    VertexBuffer!VectorVertex* lineVBuffer_;

    /// Vertex buffer storing vertices of triangles in sprites.
    VertexBuffer!VectorVertex* triVBuffer_;

public:
    /// Construct a VectorRenderer.
    ///
    /// Params:  renderer = Renderer used for graphics functionality.
    ///          dataDir  = Data directory (must contain a "shaders" subdirectory
    ///                     to load shaders from).
    ///          camera   = Reference to the camera used for viewing.
    ///
    /// Throws:  SpriteRendererInitException on failure.
    this(Renderer renderer, VFSDir dataDir, Camera2D camera)
    {
        super(renderer, dataDir, camera, "vector");
        lineVBuffer_ = renderer.createVertexBuffer!VectorVertex(PrimitiveType.Lines);
        triVBuffer_  = renderer.createVertexBuffer!VectorVertex(PrimitiveType.Triangles);
    }

    /// Destroy the SpriteRendererBase, destroying all remaining vector sprites.
    ///
    /// Must be called as the vector renderer uses manually allocated memory.
    ~this()
    {
        foreach(sprite; sprites_) if(sprite !is null)
        {
            free(sprite);
        }
        free(lineVBuffer_);
        free(triVBuffer_);
    }

    /// Create a new, empty vector sprite.
    ///
    /// The sprite returned can only be drawn by the VectorRenderer that 
    /// created it.
    VectorSprite* createVectorSprite() @trusted
    {
        auto result = alloc!VectorSprite(this);
        sprites_ ~= result;
        return result;
    }

    /// Draw a vector sprite.
    ///
    /// Must be called between calls to startDrawing() and stopDrawing();
    ///
    /// Params:  sprite   = Sprite to draw. Must be locked.
    ///          position = 2D position of the sprite.
    void drawVectorSprite(VectorSprite* sprite, const vec2 position) @trusted
    {
        assert(sprites_[].canFind(sprite),
               "Trying to draw a vector sprite that wasn't created by this VectorRenderer");
        assert(sprite.vectorRenderer_ is this,
               "Trying to draw a VectorSprite with a VectorRenderer that didn't create it");
        assert(sprite.locked, "Trying to draw an unlocked VectorSprite");

        // Upload vertices if we've not draw this vector sprite yet.
        if(sprite.hasLines && sprite.lineVBufferOffset_ == uint.max)
        {
            sprite.lineVBufferOffset_ =
                uploadVertices(sprite.lineVertices_, lineVBuffer_);
        }
        if(sprite.hasTris && sprite.triVBufferOffset_ == uint.max)
        {
            sprite.triVBufferOffset_ =
                uploadVertices(sprite.triVertices_, triVBuffer_);
        }

        uploadUniforms(position);
        if(sprite.hasLines) with(*sprite)
        {
            drawFromBuffer(lineVBuffer_, lineVBufferOffset_, lineVertices_.length);
        }
        if(sprite.hasTris) with(*sprite)
        {
            drawFromBuffer(triVBuffer_, triVBufferOffset_, triVertices_.length);
        }
    }

protected:
    override void stopDrawing_() @trusted
    {
        if(boundVBuffer_ !is null){boundVBuffer_.release();}
        boundVBuffer_ = null;
    }

    override void prepareForRendererSwitch_() @trusted
    {
        // Forces vertex data of each sprite to be reuploaded at its first draw after
        // the switch.
        foreach(sprite; sprites_)
        {
            sprite.lineVBufferOffset_ = sprite.triVBufferOffset_ = uint.max;
        }
        free(lineVBuffer_);
        free(triVBuffer_);
    }

    override void switchRenderer_() @trusted
    {
        lineVBuffer_ = renderer_.createVertexBuffer!VectorVertex(PrimitiveType.Lines);
        triVBuffer_  = renderer_.createVertexBuffer!VectorVertex(PrimitiveType.Triangles);
    }

private:
    /// Upload vertices to a vertex buffer, adding them to its end.
    ///
    /// Params:  vertices = Vertices to upload.
    ///          vbuffer  = Vertex buffer to upload to.
    uint uploadVertices(ref const Vector!VectorVertex vertices,
                        VertexBuffer!VectorVertex* vbuffer) @trusted
    {
        bool vBufferBound = vbuffer.bound;
        if(vBufferBound) {vbuffer.release();}
        vbuffer.unlock();
        const oldLength = cast(uint)vbuffer.length;
        foreach(v; 0 .. vertices.length)
        {
            vbuffer.addVertex(vertices[v]);
        }
        vbuffer.lock();
        if(vBufferBound) {vbuffer.release();}
        return oldLength;
    }

    /// Draw vertices from specified buffer.
    ///
    /// Can only be called from drawVectorSprite(), after uploading uniforms.
    ///
    /// Params:  vbuffer = Vertex buffer to draw from.
    ///          first   = Index of the first vertex to draw.
    ///          count   = Number of vertices to draw.
    void drawFromBuffer(VertexBuffer!VectorVertex* vbuffer,
                        const uint first, const size_t count) @trusted
    {
        if(boundVBuffer_ !is vbuffer)
        {
            if(boundVBuffer_ !is null) {boundVBuffer_.release();}
            vbuffer.bind();
            boundVBuffer_ = vbuffer;
        }
        renderer_.drawVertexBuffer(boundVBuffer_, null, spriteShader_, first, cast(uint)count);
    }

    /// Called by a VectorSprite at destruction to remove itself from the VectorRenderer.
    void vectorSpriteDeleted(VectorSprite* vectorSprite) @safe
    {
        // POSSIBLE OPTIMIZATION:
        // Free the vertex buffer storage used by the sprite.
        // We can use the same idea as the BinaryTexturePacker, only in 1D.
        // Maybe rename BinaryTexturePacker to 2DBinaryPacker and add a
        // 1DBinaryPacker.
        foreach(ref sprite; sprites_) if(sprite is vectorSprite)
        {
            sprite = null;
            return;
        }
        assert(false, "Deleting a nonexistent (or already deleted) sprite");
    }
}

private:

/// Vertex type used by vector sprites.
struct VectorVertex
{
    // 2D position of the vertex.
    vec2 position;
    // RGBA vertex color.
    vec4 color;
    // Padding to a 32-bit boundary.
    vec2 padding;

    mixin VertexAttributes!(vec2, AttributeInterpretation.Position,
                            vec4, AttributeInterpretation.Color,
                            vec2, AttributeInterpretation.Padding);
}


