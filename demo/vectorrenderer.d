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
    // Current line width (while building the vector sprite, before locked).
    float lineWidth_ = 1.0f;

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

    /// Set the line width of lines added in following addLine() calls.
    ///
    /// 1.0 by default.
    @property void lineWidth(const float rhs) @safe pure nothrow {lineWidth_ = rhs;}

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
        if(lineWidth_ > 0.99f && lineWidth_ < 1.01f)
        {
            lineVertices_ ~= VectorVertex(start, startColor.toVec4());
            lineVertices_ ~= VectorVertex(end,   endColor.toVec4());
            return;
        }
        // GL thick/thin lines are ugly, so we roll our own.

        // Equivalent to (v2 - v1).normal;
        const offsetBase = vec2(start.y - end.y, end.x - start.x).normalized; 
        const halfWidth  = lineWidth_ * 0.5f;
        // Offset of line vertices from start and end point of the line.
        const offset = offsetBase * halfWidth;

        // Offsets of AA vertices from start and end point of the line.
        const offsetAA = offsetBase * (halfWidth + 0.4);

        Color startColorAA = startColor;
        Color endColorAA   = endColor;
        startColorAA.a     = 0;
        endColorAA.a       = 0;

        addTriangle(start - offsetAA, startColorAA,
                    end   - offsetAA, endColorAA,
                    start - offset,   startColor);
        addTriangle(start - offset,   startColor,
                    end   - offsetAA, endColorAA,
                    end   - offset,   endColor);
        addTriangle(start - offset,   startColor,
                    end   - offset,   endColor,
                    start + offset,   startColor);
        addTriangle(start + offset,   startColor,
                    end   - offset,   endColor,
                    end   + offset,   endColor);
        addTriangle(start + offset,   startColor,
                    end   + offset,   endColor,
                    start + offsetAA, startColorAA);
        addTriangle(start + offsetAA, startColorAA,
                    end   + offset,   endColor,
                    end   + offsetAA, endColorAA);
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
    // Vector sprites created by this renderer.
    Vector!(VectorSprite*) sprites_;

    // Currently bound vertex buffer (only relevant when drawing).
    VertexBuffer!VectorVertex* boundVBuffer_ = null;

    // Vertex buffer storing vertices of lines in sprites.
    VertexBuffer!VectorVertex* lineVBuffer_;

    // Vertex buffer storing vertices of triangles in sprites.
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
    void drawVectorSprite(VectorSprite* sprite, const vec3 position) @trusted
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
        if(vBufferBound) {vbuffer.bind();}
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

import spatial.centeredsquare;
/// Draw a centered square (wireframe). Used for debugging.
///
/// Params:  renderer = VectorRenderer to draw the square.
///                     Must be between startDrawing() and stopDrawing() calls.
///          square   = Square to draw.
///          color    = Color to draw with.
void drawCenteredSquare(VectorRenderer renderer, const CenteredSquare square,
                        const Color color)
{
    auto sprite = renderer.createVectorSprite();
    scope(exit){free(sprite);}
    with(*sprite)
    {
        const h = square.halfSize;
        addLine(vec2(-h, -h), color, vec2(h, -h), color);
        addLine(vec2(h, -h), color, vec2(h, h), color);
        addLine(vec2(h, h), color, vec2(-h, h), color);
        addLine(vec2(-h, h), color, vec2(-h, -h), color);
        lock();
    }
    renderer.drawVectorSprite(sprite , vec3(square.center, 0));
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


