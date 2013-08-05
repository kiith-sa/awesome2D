//          Copyright Ferdinand Majerech 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Classes handling rendering of sprites of various types.
module demo.spriterenderer;


import std.algorithm;
import std.math;
alias std.math.round round;
import std.stdio;

import dgamevfs._;
import gl3n.aabb;

import demo.camera2d;
import demo.light;
import demo.lightmanager;
import demo.lightuniforms;
import demo.sprite;
import demo.spritepage;
import demo.spritetype;
import demo.texturepacker;
import math.math;
import memory.memory;
import spatial.boundingsphere;
import spatial.centeredsquare;
import spatial.spatialmanager;
import util.linalg;
import video.exceptions;
import video.glslshader;
import video.indexbuffer;
import video.renderer;
import video.uniform;
import video.vertexbuffer;

/// Exception thrown when a SpriteRenderer fails to initialize.
class SpriteRendererInitException : Exception 
{
    public this(string msg, string file = __FILE__, int line = __LINE__)
    {
        super(msg, file, line);
    }
}

/// Base class for sprite renderer classes.
///
/// Each sprite type has its own sprite renderer type derived from this class,
/// constructed by SpriteManager of that sprite type.
///
/// Any sprite draws must happen between calls to startDrawing() and
/// stopDrawing(). Between these calls, no renderer objects
/// (such as textures, vertex/index buffers and shaders) must be bound,
/// and, in general, no direct Renderer calls should happen.
///
/// Sprite drawing API is specific to the child classes themselves.
///
/// Renderer switching is supported through prepareForRendererSwitch() and 
/// switchRenderer().
abstract class SpriteRendererBase
{
protected:
    // Renderer used for drawing.
    Renderer renderer_;

    // Are we currently drawing sprites? If true, spriteShader_ is bound.
    bool drawing_;

    // Reference to the camera used to set up the projection matrix.
    Camera2D camera_;

    // Game data directory (to load shaders).
    VFSDir dataDir_;

    // Shader program used to draw sprites. The lighting model is implemented on shader.
    GLSLShaderProgram* spriteShader_;

    // Base part of filenames of shader files used.  
    //
    // E.g. "sprite" for "sprite.vert" and "sprite.frag".
    string shaderBaseName_;

public:
    /// Construct a SpriteRendererBase.
    ///
    /// Params:  renderer       = Renderer used for graphics functionality.
    ///          dataDir        = Data directory (must contain a "shaders" subdirectory
    ///                           to load shaders from).
    ///          camera         = Reference to the camera used for viewing.
    ///          shaderBaseName = Base part of filenames of shader files used
    ///                           for this SpriteRenderer. (E.g. "sprite" for
    ///                           "sprite.vert" and "sprite.frag")
    ///
    /// Throws:  SpriteRendererInitException on failure.
    this(Renderer renderer, VFSDir dataDir, Camera2D camera, string shaderBaseName) @safe
    {
        renderer_       = renderer;
        dataDir_        = dataDir;
        camera_         = camera;
        shaderBaseName_ = shaderBaseName;
        initializeShader(shaderBaseName_);
    }

    /// Destroy the SpriteRendererBase, freeing all used resources.
    ///
    /// Must be called as sprite renderers use manually allocated memory.
    ~this()
    {
        assert(spriteShader_ !is null, "Sprite shader null at SpriteRenderer destruction");
        free(spriteShader_);
    }

    /// Start drawing sprites.
    ///
    /// Must be called before any calls to sprite type specific drawSprite() methods.
    ///
    /// Binds SpriteRenderer's sprite shader, and enables alpha blending.
    /// Also, during drawing, the SpriteRenderer manages sprite texture, vertex and 
    /// index buffer binds.
    /// No other shader, texture, vertex or index buffer can be bound until stopDrawing() 
    /// is called, and if alpha blending is disabled between sprite draws, 
    /// it must be reenabled before the next sprite draw.
    ///
    /// Also, no sprite should be deleted while drawing.
    ///
    /// This is also the point when camera state is passed to the shader.
    /// While drawing, any changes to the camera will have no effect.
    final void startDrawing() @trusted
    {
        assert(!drawing_, "SpriteRenderer.startDrawing() called when already drawing");
        drawing_ = true;
        renderer_.pushBlendMode(BlendMode.Alpha);
        startDrawing_();
        resetUniforms();
        spriteShader_.bind();
    }

    /// Stop drawing sprites.
    ///
    /// Must be called after drawing sprites to allow other drawing operations.
    final void stopDrawing() @trusted
    {
        assert(drawing_, "SpriteRenderer.stopDrawing() called without calling startDrawing()");
        assert(renderer_.blendMode == BlendMode.Alpha,
               "Non-alpha blend mode before stopping sprite drawing");

        spriteShader_.release();
        stopDrawing_();
        renderer_.popBlendMode();
        drawing_           = false;
    }

    /// Are we drawing at the moment?
    final @property bool drawing() @safe const pure nothrow {return drawing_;}

    /// When replacing the renderer, this must be called before the renderer is destroyed.
    final void prepareForRendererSwitch() @safe
    {
        assert(!drawing_,
               "Trying to change Renderer while drawing with a SpriteRenderer");
        prepareForRendererSwitch_();
        // Deinit the shader program for now.
        deinitializeShader();
        renderer_ = null;
    }

    /// When replacing the renderer, this must be called to pass the new renderer.
    ///
    /// This will reload the sprite shader, which might take a while.
    final void switchRenderer(Renderer newRenderer) @safe
    {
        assert(renderer_ is null,
               "switchRenderer() called without prepareForRendererSwitch()");
        assert(!drawing_,
               "Trying to change Renderer while drawing with a SpriteRenderer");
        renderer_ = newRenderer;
        switchRenderer_();
        // Reload the shader, reset uniforms, init uniform handles.
        initializeShader(shaderBaseName_);
    }

protected:
    // Code the sprite-specific sprite renderer must execute before drawing sprites.
    void startDrawing_() @trusted;
    // Code the sprite-specific sprite renderer must execute after drawing sprites.
    void stopDrawing_() @trusted;

    // Initialize handles and default values of uniforms used.
    //
    // Called during construction.
    //
    // Throws:  GLSLException if a uniform was not found in the shader.
    void initializeUniforms();

    // Reset all uniforms, forcing them to be reuploaded at next draw.
    void resetUniforms() @safe pure nothrow;

    // Implementation-specific code executed before a renderer switch.
    void prepareForRendererSwitch_() @safe {}

    // Implementation-specific code executed during a renderer switch.
    //
    // renderer_ is already set to the new renderer when this is called.
    void switchRenderer_() @safe {}

private:
    // Deinitialize the sprite shader (at destruction or when switching renderers).
    void deinitializeShader() @trusted
    {
        free(spriteShader_);
    }

    // Initialize the sprite shader.
    void initializeShader(string shaderBaseName) @trusted
    {
        spriteShader_ = renderer_.createGLSLShader();
        try
        {
            // Load the shader.
            auto shaderDir = dataDir_.dir("shaders");
            auto vertFile  = shaderDir.file(shaderBaseName ~ ".vert");
            auto fragFile  = shaderDir.file(shaderBaseName ~ ".frag");
            char[] vertSource  = allocArray!char(cast(size_t)vertFile.bytes);
            scope(exit){free(vertSource);}
            char[] fragSource  = allocArray!char(cast(size_t)fragFile.bytes);
            scope(exit){free(fragSource);}
            vertFile.input.read(cast(void[])vertSource);
            fragFile.input.read(cast(void[])fragSource);
            const vertexShader   = spriteShader_.addVertexShader(cast(string)vertSource);
            const fragmentShader = spriteShader_.addFragmentShader(cast(string)fragSource);

            spriteShader_.lock();

            initializeUniforms();
        }
        catch(VFSException e)
        {
            throw new SpriteRendererInitException("Couldn't load sprite shader: " ~ e.msg);
        }
        catch(GLSLException e)
        {
            throw new SpriteRendererInitException("Error in sprite shader: " ~ e.msg);
        }
    }
}

//XXX DOCUMENT UNIFORMS THE PROGAM MUST HAVE
/// Sprite renderer used to draw sprites with 3D lighting support.
///
/// Has methods to register/unregister point and directional lights 
/// (with limits on maximum number of concurrently used lights; currently 
/// 2 directional and 6 point lights. Can also set ambient lighting.
/// Lights can be swapped between sprite draws to use more than maximum
/// lights on the scene (as long as no more than maximum lights affect 
/// any single sprite).
///
/// Also supports 3D clipping - any pixels with 3D positions outside of 
/// the clipped area will not be drawn.
class Sprite3DRenderer : SpriteRendererBase
{
private:
    alias GenericSpritePage!(SpriteType3D, BinaryTexturePacker) SpritePage;

    // Sprite page whose textures, vertex and index buffer are currently bound.
    //
    // Only matters when drawing.
    SpritePage* boundSpritePage_ = null;

    // Vertical view angle.
    float verticalAngleDegrees_;

    // Handle to the sprite 3D position uniform.
    uint positionUniformHandle_;

    // Uniform passing vertical view angle in radians to the GPU.
    Uniform!float verticalAngleUniform_;
    // Projection matrix of the camera.
    Uniform!mat4 projectionUniform_;

    // Diffuse color texture unit.
    Uniform!int diffuseSamplerUniform_;
    // Normal texture unit.
    Uniform!int normalSamplerUniform_;
    // Offset texture unit.
    Uniform!int offsetSamplerUniform_;

    // Minimum bounds of the 3D clipped area. Any pixels outside this area will be discarded.
    Uniform!vec3 minClipBoundsUniform_;
    // Maximum bounds of the 3D clipped area. Any pixels outside this area will be discarded.
    Uniform!vec3 maxClipBoundsUniform_;

    // Inverses of gamma correction exponents for every color channel.
    vec3 invGamma_ = vec3(2.2f, 2.2f, 2.2f);

    // Manages light sources; maps many virtual lights to a few actual lights and reduces 
    // light uniform reuploads.
    LightManager lightManager_;

    // Wraps uniform values representing light sources.
    LightUniforms lightUniforms_;

package:
    /// Construct a Sprite3DRenderer.
    ///
    /// Params:  renderer     = Renderer used for graphics functionality.
    ///          dataDir      = Data directory (must contain a "shaders" subdirectory
    ///                         to load shaders from).
    ///          camera       = Reference to the camera used for viewing.
    ///
    /// Throws:  SpriteRendererInitException on failure.
    this(Renderer renderer, VFSDir dataDir, Camera2D camera) @safe
    {
        verticalAngleDegrees_ = 30.0;
        super(renderer, dataDir, camera, "sprite");
        lightManager_ = new LightManager(&lightUniforms_);
    }

public:
    /// Destroy the Sprite3DRenderer.
    ~this()
    {
        destroy(lightManager_);
        lightManager_ = null;
    }

    /// Get the light manager to manage lights used with this Sprite3DRenderer.
    ///
    /// Note that the LightManager must be locked before any drawSprite() call.
    @property LightManager lightManager() @safe pure nothrow {return lightManager_;}

    /// Set vertical view angle in degrees (30.0 by default).
    @property void verticalAngle(const float rhs) @safe pure nothrow 
    {
        verticalAngleDegrees_ = rhs;
        verticalAngleUniform_.value = rhs * degToRad;
    }

    /// Draw a sprite at specified 3D position.
    ///
    /// Must be called between calls to startDrawing() and stopDrawing().
    /// Also, the LightManager passed to the constructor of this Sprite3DRenderer
    /// must be locked.
    ///
    /// Params:  sprite   = Pointer to the sprite to draw.
    ///          position = Position of the sprite in 3D space. The final 2D position
    ///                     is determined by the vertical angle of the SpriteRenderer.
    ///          rotation = Rotation of the sprite around the X, Y and Z axis.
    ///                     (At the moment, only Z affects the graphics as the 
    ///                     sprite format only supports Z rotation).
    void drawSprite(Sprite* sprite, vec3 position, const vec3 rotation) @trusted
    {
        assert(drawing_,
               "Sprite3DRenderer.drawSprite() called without calling startDrawing()");
        assert(renderer_.blendMode == BlendMode.Alpha,
               "Non-alpha blend mode when drawing a sprite");

        // Taking X and Y sprite size instead of bbox size is not ideal,
        // but likely "good enough".
        lightManager_.setLitArea
            (CenteredSquare(position.xy, max(sprite.width, sprite.height) * 0.5));
        uploadUniforms(position);

        const facingIndex = sprite.closestFacing(rotation);
        Sprite.Facing* facing = &(sprite.facings_[facingIndex]);
        SpritePage* page = cast(SpritePage*)facing.spritePage;
        // Don't rebind a sprite page if we don't have to.
        if(boundSpritePage_ != page)
        {
            if(boundSpritePage_ !is null){boundSpritePage_.release();}
            page.bind();
            boundSpritePage_ = page;
        }

        const indexOffset = facing.indexBufferOffset;
        assert(indexOffset % 6 == 0, "Sprite indices don't form sextets");
        // Assuming a vertex quadruplet per image, added in same order
        // as the indices. See vertex/index adding code in sprite type 
        // structs.
        const minVertex = (indexOffset / 6) * 4;
        const maxVertex = minVertex + 3;

        renderer_.drawVertexBuffer(page.vertices_, page.indices_, spriteShader_,
                                   facing.indexBufferOffset, 6, minVertex, maxVertex);
    }

    /// Set 3D area to draw in. Any pixels outside of this area will be discarded.
    @property void clipBounds(const AABB rhs) @safe pure nothrow 
    {
        minClipBoundsUniform_.value = rhs.min;
        maxClipBoundsUniform_.value = rhs.max;
    }

    /// Set the inverse gamma correction exponents for the R, G and B channels.
    ///
    /// By default, this is vec3(2.2f, 2.2f, 2.2f).
    @property void invGamma(const vec3 rhs) @safe pure nothrow 
    {
        lightUniforms_.invGamma = rhs;
    }

protected:
    override void startDrawing_() @safe pure nothrow
    {
        projectionUniform_.value = camera_.projection;
    }

    override void stopDrawing_() @trusted
    {
        if(boundSpritePage_ !is null) {boundSpritePage_.release();}
        boundSpritePage_   = null;
    }

    override void initializeUniforms()
    {
        // Get handles to access uniforms with.
        with(*spriteShader_)
        {
            verticalAngleUniform_         = Uniform!float(getUniformHandle("verticalAngle"));
            projectionUniform_            = Uniform!mat4(getUniformHandle("projection"));
            diffuseSamplerUniform_        = Uniform!int(getUniformHandle("texDiffuse"));
            normalSamplerUniform_         = Uniform!int(getUniformHandle("texNormal"));
            offsetSamplerUniform_         = Uniform!int(getUniformHandle("texOffset"));
            minClipBoundsUniform_         = Uniform!vec3(getUniformHandle("minClipBounds"));
            maxClipBoundsUniform_         = Uniform!vec3(getUniformHandle("maxClipBounds"));

            verticalAngleUniform_.value   = verticalAngleDegrees_ * degToRad;
            diffuseSamplerUniform_.value  = SpriteTextureUnit.Diffuse;
            normalSamplerUniform_.value   = SpriteTextureUnit.Normal;
            offsetSamplerUniform_.value   = SpriteTextureUnit.Offset;
            minClipBoundsUniform_.value   = vec3(-100000.0f, -100000.0f, -100000.0f);
            maxClipBoundsUniform_.value   = vec3(100000.0f,  100000.0f, 100000.0f);

            positionUniformHandle_        = getUniformHandle("spritePosition3D");

            lightUniforms_.useProgram(spriteShader_);
            lightUniforms_.invGamma = invGamma_;
        }
    }

    override void resetUniforms() @safe pure nothrow
    {
        verticalAngleUniform_.reset();
        diffuseSamplerUniform_.reset();
        normalSamplerUniform_.reset();
        offsetSamplerUniform_.reset();
        minClipBoundsUniform_.reset();
        maxClipBoundsUniform_.reset();

        lightUniforms_.reset();
    }

private:
    // Upload uniforms that need to be uploaded before drawing.
    //
    // Params:  position = 3D position of the sprite.
    void uploadUniforms(const vec3 position)
    {
        // The uniforms encapsulated in Uniform structs don't have to be reuploaded every time.

        // View angle and projection.
        verticalAngleUniform_.uploadIfNeeded(spriteShader_);
        projectionUniform_.uploadIfNeeded(spriteShader_);

        // Texture units used by specified textures.
        diffuseSamplerUniform_.uploadIfNeeded(spriteShader_);
        normalSamplerUniform_.uploadIfNeeded(spriteShader_);
        offsetSamplerUniform_.uploadIfNeeded(spriteShader_);

        // Clipping bounds.
        minClipBoundsUniform_.uploadIfNeeded(spriteShader_);
        maxClipBoundsUniform_.uploadIfNeeded(spriteShader_);

        lightUniforms_.upload();

        // Reuploaded for each sprite.
        spriteShader_.setUniform(positionUniformHandle_, position);
    }
}

/// Base class for sprite renderers that don't support lighting.
abstract class SpriteUnlitRenderer : SpriteRendererBase
{
private:
    // Vertical view angle if dimetric is enabled.
    float verticalAngleDegrees_;

    // Handle to the sprite 2D position uniform.
    uint positionUniformHandle_;

    // Uniform passing vertical view angle in radians to the GPU.
    Uniform!float verticalAngleUniform_;

    // Projection matrix of the camera.
    Uniform!mat4 projectionUniform_;

    // Minimum bounds of the 2D clipped area. Any pixels outside this area will be discarded.
    Uniform!vec2 minClipBoundsUniform_;
    // Maximum bounds of the 2D clipped area. Any pixels outside this area will be discarded.
    Uniform!vec2 maxClipBoundsUniform_;
    // Use a dimetric projection?
    Uniform!bool dimetricUniform_;

public:
    /// Construct a SpriteUnlitRenderer.
    ///
    /// Params:  renderer       = Renderer used for graphics functionality.
    ///          dataDir        = Data directory (must contain a "shaders" subdirectory
    ///                           to load shaders from).
    ///          camera         = Reference to the camera used for viewing.
    ///          shaderBaseName = Base part of filenames of shader files used
    ///                           for this SpriteRenderer. (E.g. "sprite" for
    ///                           "sprite.vert" and "sprite.frag")
    ///
    /// Throws:  SpriteRendererInitException on failure.
    this(Renderer renderer, VFSDir dataDir, Camera2D camera, string shaderBaseName) @safe
    {
        verticalAngleDegrees_ = 30.0;
        super(renderer, dataDir, camera, shaderBaseName);
    }

    /// Set 2D area to draw in. Any pixels outside of this area will be discarded.
    @property void clipBounds(const vec2 min, const vec2 max) @safe pure nothrow 
    {
        assert(min.x <= max.x && min.y <= max.y, "Invalid 2D clip bounds");
        minClipBoundsUniform_.value = min;
        maxClipBoundsUniform_.value = max;
    }

    /// Use a dimetric projection?
    ///
    /// Use together with verticalAngle.
    @property void useDimetric(bool rhs) @safe pure nothrow {dimetricUniform_.value = rhs;}

    /// Set vertical view angle in degrees (30.0 by default).
    ///
    /// Only valid when useDimetric is set to true.
    /// Useful to position plain sprites in world coordinates.
    @property void verticalAngle(const float rhs) @safe pure nothrow 
    {
        verticalAngleDegrees_ = rhs;
        verticalAngleUniform_.value = rhs * degToRad;
    }

protected:
    override void startDrawing_() @safe pure nothrow
    {
        projectionUniform_.value = camera_.projection;
    }

    override void resetUniforms() @safe pure nothrow
    {
        minClipBoundsUniform_.reset();
        maxClipBoundsUniform_.reset();
        dimetricUniform_.reset();
        verticalAngleUniform_.reset();
    }

    override void initializeUniforms()
    {
        const dimetric = dimetricUniform_.value;
        with(*spriteShader_)
        {
            verticalAngleUniform_         = Uniform!float(getUniformHandle("verticalAngle"));
            dimetricUniform_              = Uniform!bool(getUniformHandle("dimetric"));
            projectionUniform_            = Uniform!mat4(getUniformHandle("projection"));
            minClipBoundsUniform_         = Uniform!vec2(getUniformHandle("min2DClipBounds"));
            maxClipBoundsUniform_         = Uniform!vec2(getUniformHandle("max2DClipBounds"));
            positionUniformHandle_        = getUniformHandle("spritePosition3D");

            verticalAngleUniform_.value   = verticalAngleDegrees_ * degToRad;
            dimetricUniform_.value        = dimetric;
            minClipBoundsUniform_.value   = vec2(-100000.0f, -100000.0f);
            maxClipBoundsUniform_.value   = vec2(100000.0f,  100000.0f);
        }
    }

    // Upload uniforms that need to be uploaded before drawing.
    //
    // Params:  position = 3D position of the bottom-left corner of the sprite.
    void uploadUniforms(const vec3 position) @trusted
    {
        // The uniforms encapsulated in Uniform structs don't have to be reuploaded every time.

        verticalAngleUniform_.uploadIfNeeded(spriteShader_);
        projectionUniform_.uploadIfNeeded(spriteShader_);
        minClipBoundsUniform_.uploadIfNeeded(spriteShader_);
        maxClipBoundsUniform_.uploadIfNeeded(spriteShader_);
        dimetricUniform_.uploadIfNeeded(spriteShader_);
        // Reuploaded for each sprite.
        with(*spriteShader_)
        {
            setUniform(positionUniformHandle_, position);
        }
    }
}


/// Base class for sprite renderers drawing pixel (i.e. not vector) data without lighting.
abstract class SpriteUnlitPixelRenderer(SpritePage) : SpriteUnlitRenderer
{
private:
    // Sprite page whose textures, vertex and index buffer are currently bound.
    //
    // Only matters when drawing.
    SpritePage* boundSpritePage_ = null;

    // Diffuse color texture unit.
    Uniform!int diffuseSamplerUniform_;

public:
    /// Construct a SpriteUnlitPixelRenderer.
    ///
    /// See_Also: SpriteUnlitRenderer.this()
    this(Renderer renderer, VFSDir dataDir, Camera2D camera, string shaderBaseName) @safe
    {
        super(renderer, dataDir, camera, shaderBaseName);
    }

    /// Draw a sprite at specified 2D position.
    ///
    /// Must be called between calls to startDrawing() and stopDrawing().
    ///
    /// Params:  sprite   = Pointer to the sprite to draw.
    ///          position = Position of the bottom-left corner of the sprite
    ///                     in plain 2D space (pixels).
    void drawSprite(Sprite* sprite, vec2 position) @trusted
    {
        assert(drawing_,
               "SpritePlainRenderer.drawSprite() called without calling startDrawing()");
        assert(renderer_.blendMode == BlendMode.Alpha,
               "Non-alpha blend mode when drawing a sprite");
        // Get on a whole-pixel boundary to avoid blurriness.
        position.x = round(position.x);
        position.y = round(position.y);

        uploadUniforms(vec3(position, 0.0f));

        assert(sprite.facings_.length == 1,
               "SpritePlainRenderer trying to draw a sprite with multiple facings");
        Sprite.Facing* facing = &(sprite.facings_[0]);
        SpritePage* page = cast(SpritePage*)facing.spritePage;
        // Don't rebind a sprite page if we don't have to.
        if(boundSpritePage_ != page)
        {
            if(boundSpritePage_ !is null){boundSpritePage_.release();}
            page.bind();
            boundSpritePage_ = page;
        }

        const indexOffset = facing.indexBufferOffset;
        assert(indexOffset % 6 == 0, "Sprite indices don't form sextets");
        // Assuming a vertex quadruplet per image, added in same order
        // as the indices. See vertex/index adding code in sprite type 
        // structs.
        const minVertex = (indexOffset / 6) * 4;
        const maxVertex = minVertex + 3;

        renderer_.drawVertexBuffer(page.vertices_, page.indices_, spriteShader_,
                                   facing.indexBufferOffset, 6, minVertex, maxVertex);
    }

protected:
    override void stopDrawing_() @trusted
    {
        if(boundSpritePage_ !is null) {boundSpritePage_.release();}
        boundSpritePage_   = null;
    }

    override void resetUniforms() @safe pure nothrow
    {
        super.resetUniforms();
        diffuseSamplerUniform_.reset();
    }

    override void initializeUniforms()
    {
        super.initializeUniforms();
        diffuseSamplerUniform_ = Uniform!int(spriteShader_.getUniformHandle("texDiffuse"));
        diffuseSamplerUniform_.value  = SpriteTextureUnit.Diffuse;
    }

    override void uploadUniforms(const vec3 position) @trusted
    {
        super.uploadUniforms(position);
        diffuseSamplerUniform_.uploadIfNeeded(spriteShader_);
    }
}

private alias GenericSpritePage!(SpriteTypePlain, BinaryTexturePacker) PlainSpritePage;
/// Sprite renderer used to draw plain RGBA sprites.
///
/// These are drawn in plain 2D space, not dimetric.
class SpritePlainRenderer : SpriteUnlitPixelRenderer!PlainSpritePage
{
public:
    /// Construct a SpritePlainRenderer.
    ///
    /// Params:  renderer = Renderer used for graphics functionality.
    ///          dataDir  = Data directory (must contain a "shaders" subdirectory
    ///                     to load shaders from).
    ///          camera   = Reference to the camera used for viewing.
    ///
    /// Throws:  SpriteRendererInitException on failure.
    this(Renderer renderer, VFSDir dataDir, Camera2D camera) @safe
    {
        super(renderer, dataDir, camera, "plainSprite");
    }
}
