//          Copyright Ferdinand Majerech 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Classes handling rendering of sprites of various types.
module demo.spriterenderer;


import std.algorithm;
import std.math;
alias std.math.round round;

import dgamevfs._;
import gl3n.aabb;

import demo.camera2d;
import demo.light;
import demo.sprite;
import demo.spritepage;
import demo.spritetype;
import demo.texturepacker;
import math.math;
import memory.memory;
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
        renderer_ = renderer;
        dataDir_  = dataDir;
        camera_   = camera;
        initializeShader(shaderBaseName);
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
        // Reload the shader, reset uniforms, init uniform handles.
        initializeShader("sprite");
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

    void prepareForRendererSwitch_() @safe {}

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
public:
    // Maximum number of directional lights supported.
    //
    // This is hardcoded in the sprite fragment shader. If changed, update the
    // shader as well as any 2's found in documentation/errors in this file.
    enum maxDirectionalLights = 2;

    // Maximum number of point lights supported.
    //
    // This is hardcoded in the sprite fragment shader. If changed, update the
    // shader as well as any 6's found in documentation/errors in this file.
    enum maxPointLights = 6;

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

    // Ambient light color.
    Uniform!vec3 ambientLightUniform_;

    // We pass every light attribute as a separate array as there is no
    // way to pass struct arrays to shaders (at least with GL 2.1).

    // Directions of currently enabled directional lights.
    Uniform!(vec3[maxDirectionalLights]) directionalDirectionsUniform_;
    // Diffuse colors of currently enabled directional lights.
    Uniform!(vec3[maxDirectionalLights]) directionalDiffuseUniform_;
    // Do directional uniforms need to be updated? (E.g. after lights have been changed)
    bool directionalUniformsNeedUpdate_;

    // Positions of currently enabled point lights.
    Uniform!(vec3[maxPointLights]) pointPositionsUniform_;
    // Diffuse colors of currently enabled point lights.
    Uniform!(vec3[maxPointLights]) pointDiffuseUniform_;
    // Attenuations of currently enabled point lights.
    Uniform!(float[maxPointLights]) pointAttenuationsUniform_;
    // Do point uniforms need to be updated? (E.g. after lights have been changed)
    bool pointUniformsNeedUpdate_;

    // Number of directional light pointers currently stored in directionalLights_.
    uint directionalLightsUsed_ = 0;
    // Pointers to registered directional lights. Fixed size as the maximum number 
    // of directional lights is known at compile time. Only the first 
    // directionalLightsUsed_ elements are valid.
    const(DirectionalLight)*[maxDirectionalLights] directionalLights_;

    // Number of point light pointers currently stored in pointLights_.
    uint pointLightsUsed_ = 0;
    // Pointers to registered point lights. Fixed size as the maximum number 
    // of point lights is known at compile time. Only the first 
    // pointLightsUsed_ elements are valid.
    const(PointLight)*[maxPointLights] pointLights_;

package:
    /// Construct a Sprite3DRenderer.
    ///
    /// Params:  renderer = Renderer used for graphics functionality.
    ///          dataDir  = Data directory (must contain a "shaders" subdirectory
    ///                     to load shaders from).
    ///          camera   = Reference to the camera used for viewing.
    ///
    /// Throws:  SpriteRendererInitException on failure.
    this(Renderer renderer, VFSDir dataDir, Camera2D camera) @safe
    {
        verticalAngleDegrees_ = 30.0;
        super(renderer, dataDir, camera, "sprite");
    }

public:
    /// Set vertical view angle in degrees (30.0 by default).
    @property void verticalAngle(const float rhs) @safe pure nothrow 
    {
        verticalAngleDegrees_ = rhs;
        verticalAngleUniform_.value = rhs * degToRad;
    }

    /// Draw a sprite at specified 3D position.
    ///
    /// Must be called between calls to startDrawing() and stopDrawing().
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
        // Get on a whole-pixel boundary to avoid blurriness.
        position.x = cast(int)(position.x);
        position.y = cast(int)(position.y);

        updateUniforms(position);

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

    /// Set the ambient light color.
    @property void ambientLight(const vec3 rhs) @safe pure nothrow
    {
        ambientLightUniform_.value = rhs;
    }

    /// Register a directional (infinite-distance) light, and use it in future sprite draws.
    ///
    /// Useful for light sources with "parallel" rays such as the sun.
    ///
    /// Note: After any modifications to registered directional lights,
    ///       a call to directionalLightsChanged() is needed for the changes
    ///       to take effect.
    ///
    /// Note: Number of directional lights that may be registered simultaneously
    ///       is limited by maxDirectionalLights. Trying to register more will
    ///       result in undefined behavior (or assertion failure in debug build).
    ///
    /// Params:  light = Pointer to the light to register. The light must exist
    ///                  at the location the pointer points to until the light
    ///                  is unregistered or the SpriteRenderer is destroyed.
    void registerDirectionalLight(const(DirectionalLight)* light) @safe pure nothrow
    {
        assert(directionalLightsUsed_ <= maxDirectionalLights, 
               "Only 2 directional lights are supported; can't register more.");
        directionalLights_[directionalLightsUsed_++] = light;
        directionalUniformsNeedUpdate_ = true;
    }

    /// Unregister a directional light so it's not used in future sprite draws.
    ///
    /// Params:  light = Pointer to the light to unregister. Must be a pointer
    ///                  to one of currently registered lights.
    void unregisterDirectionalLight(const(DirectionalLight)* light) @safe pure nothrow
    {
        directionalUniformsNeedUpdate_ = true;
        foreach(idx, ref l; directionalLights_[0 .. directionalLightsUsed_]) if(l is light)
        {
            // Swap the last used light with one we're removing. 
            // Then we can just decrease directionalLightsUsed_ and the swapped 
            // pointer will get overwritten on next registerDirectionalLight().
            swap(l, directionalLights_[directionalLightsUsed_ - 1]);
            --directionalLightsUsed_;
            return;
        }
        assert(false, "Unregistering a directional light that "
               "was not registered, or is already unregistered.");
    }

    /// Must be called for any changes in parameters of registered directional lights to take effect.
    void directionalLightsChanged() @safe pure nothrow
    {
        directionalUniformsNeedUpdate_ = true;
    }

    /// Register a point light, and use it in future sprite draws.
    ///
    /// Useful for light sources such as lamps, explosions and so on.
    ///
    /// Note: After any modifications to registered point lights,
    ///       a call to pointLightsChanged() is needed for the changes to take effect.
    ///
    /// Note: Number of point lights that may be registered simultaneously.
    ///       is limited by maxPointLights. Trying to register more will 
    ///       result in undefined behavior (or assertion failure in debug build).
    ///
    ///       Repeatedly registering and unregistering lights can be used to 
    ///       emulate more lights than the maximum light count; every
    ///       individual draw supports only maxPointLights point lights but
    ///       these can be different for each draw.
    ///
    /// Params:  light = Pointer to the light to register. The light must exist
    ///                  at the location the pointer points to until the light
    ///                  is unregistered or the SpriteRenderer is destroyed.
    void registerPointLight(const(PointLight)* light) @safe pure nothrow
    {
        assert(pointLightsUsed_ <= maxPointLights, 
               "Only 6 point lights are supported; can't register more.");
        pointLights_[pointLightsUsed_++] = light;
        pointUniformsNeedUpdate_ = true;
    }

    /// Unregister a point light so it's not used in future sprite draws.
    ///
    /// Params:  light = Pointer to the light to unregister. Must be a pointer
    ///                  to one of currently registered lights.
    void unregisterPointLight(const(PointLight)* light) @safe pure nothrow
    {
        pointUniformsNeedUpdate_ = true;
        foreach(idx, ref l; pointLights_[0 .. pointLightsUsed_]) if(l is light)
        {
            // Swap the last used light with the one we're removing. 
            // Then we can just decrease pointLightsUsed_ and the swapped 
            // pointer will get overwritten on next registerPointLight().
            swap(l, pointLights_[pointLightsUsed_ - 1]);
            --pointLightsUsed_;
            return;
        }
        assert(false, "Unregistering a point light that "
               "was not registered, or is already unregistered.");
    }

    /// Must be called for any changes in parameters of registered point lights to take effect.
    void pointLightsChanged() @safe pure nothrow
    {
        pointUniformsNeedUpdate_ = true;
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
        directionalUniformsNeedUpdate_ = true;
        pointUniformsNeedUpdate_       = true;
        // Ambient is stored directly in the Uniform struct - need to preserve it 
        // between renderer reloads.
        const previousAmbient = ambientLightUniform_.value;
        // Get handles to access uniforms with.
        with(*spriteShader_)
        {
            verticalAngleUniform_         = Uniform!float(getUniformHandle("verticalAngle"));
            projectionUniform_            = Uniform!mat4(getUniformHandle("projection"));
            diffuseSamplerUniform_        = Uniform!int(getUniformHandle("texDiffuse"));
            normalSamplerUniform_         = Uniform!int(getUniformHandle("texNormal"));
            offsetSamplerUniform_         = Uniform!int(getUniformHandle("texOffset"));
            ambientLightUniform_          = Uniform!vec3(getUniformHandle("ambientLight"));
            minClipBoundsUniform_         = Uniform!vec3(getUniformHandle("minClipBounds"));
            maxClipBoundsUniform_         = Uniform!vec3(getUniformHandle("maxClipBounds"));
            directionalDirectionsUniform_ = Uniform!(vec3[maxDirectionalLights]) 
                                                (getUniformHandle("directionalDirections"));
            directionalDiffuseUniform_    = Uniform!(vec3[maxDirectionalLights])
                                                (getUniformHandle("directionalDiffuse"));
            pointPositionsUniform_        = Uniform!(vec3[maxPointLights])
                                                (getUniformHandle("pointPositions"));
            pointDiffuseUniform_          = Uniform!(vec3[maxPointLights])
                                                (getUniformHandle("pointDiffuse"));
            pointAttenuationsUniform_     = Uniform!(float[maxPointLights])
                                                (getUniformHandle("pointAttenuations"));

            verticalAngleUniform_.value   = verticalAngleDegrees_ * degToRad;
            diffuseSamplerUniform_.value  = SpriteTextureUnit.Diffuse;
            normalSamplerUniform_.value   = SpriteTextureUnit.Normal;
            offsetSamplerUniform_.value   = SpriteTextureUnit.Offset;
            ambientLightUniform_.value    = previousAmbient;
            minClipBoundsUniform_.value   = vec3(-100000.0f, -100000.0f, -100000.0f);
            maxClipBoundsUniform_.value   = vec3(100000.0f,  100000.0f, 100000.0f);

            positionUniformHandle_        = getUniformHandle("spritePosition3D");
        }
    }

    override void resetUniforms() @safe pure nothrow
    {
        verticalAngleUniform_.reset();
        diffuseSamplerUniform_.reset();
        normalSamplerUniform_.reset();
        offsetSamplerUniform_.reset();
        ambientLightUniform_.reset();
        minClipBoundsUniform_.reset();
        maxClipBoundsUniform_.reset();
        directionalDirectionsUniform_.reset();
        directionalDiffuseUniform_.reset();
        pointPositionsUniform_.reset();
        pointDiffuseUniform_.reset();
        pointAttenuationsUniform_.reset();
    }

private:
    // Update and upload uniforms before drawing.
    void updateUniforms(const vec3 spritePosition)
    {
        if(directionalUniformsNeedUpdate_) {updateDirectionalUniforms();}
        if(pointUniformsNeedUpdate_)       {updatePointUniforms();}

        uploadUniforms(spritePosition);
    }

    // Update data to upload as directional light uniforms.
    void updateDirectionalUniforms() @safe pure nothrow
    {
        // This will probably need optimization (but need a stress test first).
        //
        // Currently we just overwrite all data but much of it could be retained
        // as lights are not always modified.
        foreach(l; 0 .. directionalLightsUsed_)
        {
            directionalDirectionsUniform_.value[l] = directionalLights_[l].direction;
            directionalDirectionsUniform_.value[l].normalize;
            const color = directionalLights_[l].diffuse;
            directionalDiffuseUniform_.value[l]    = vec3(color.toVec4.rgb);
        }
        // Due to optimization, the shader always processes all lights,
        // including those that are unspecified, so we specify data that
        // will result in no effect (black color, etc.).
        directionalDirectionsUniform_.value[directionalLightsUsed_ .. $] = vec3(0.0, 0.0, 1.0);
        directionalDiffuseUniform_.value[directionalLightsUsed_ .. $]    = vec3(0.0, 0.0, 0.0);

        // Force reupload.
        directionalDirectionsUniform_.reset();
        directionalDiffuseUniform_.reset();

        directionalUniformsNeedUpdate_ = false;
    }

    // Update data to upload as point light uniforms.
    void updatePointUniforms() @safe pure nothrow
    {
        // This will probably need optimization (but need a stress test first).
        //
        // Currently we just overwrite all data but much of it could be retained
        // as lights are not always modified.
        foreach(l; 0 .. pointLightsUsed_)
        {
            const color           = pointLights_[l].diffuse;
            const colorNormalized = vec3(color.toVec4.rgb);

            pointPositionsUniform_.value[l]    = pointLights_[l].position;
            pointDiffuseUniform_.value[l]      = colorNormalized;
            pointAttenuationsUniform_.value[l] = pointLights_[l].attenuation;
        }
        // Due to optimization, the shader always processes all lights,
        // including those that are unspecified, so we specify data that
        // will result in no effect (black color, etc.).
        pointPositionsUniform_.value[pointLightsUsed_ .. $]    = vec3(0.0, 0.0, 0.0);
        pointDiffuseUniform_.value[pointLightsUsed_ .. $]      = vec3(0.0, 0.0, 0.0);
        pointAttenuationsUniform_.value[pointLightsUsed_ .. $] = 1.0f;

        // Force reupload.
        pointPositionsUniform_.reset();
        pointDiffuseUniform_.reset();
        pointAttenuationsUniform_.reset();

        pointUniformsNeedUpdate_ = false;
    }

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

        // Ambient light.
        ambientLightUniform_.uploadIfNeeded(spriteShader_);

        // Directional lights.
        directionalDirectionsUniform_.uploadIfNeeded(spriteShader_);
        directionalDiffuseUniform_.uploadIfNeeded(spriteShader_);

        // Point lights.
        pointPositionsUniform_.uploadIfNeeded(spriteShader_);
        pointDiffuseUniform_.uploadIfNeeded(spriteShader_);
        pointAttenuationsUniform_.uploadIfNeeded(spriteShader_);

        // Reuploaded for each sprite.
        with(*spriteShader_)
        {
            setUniform(positionUniformHandle_, position);
        }
    }
}

/// Sprite renderer used to draw plain RGBA sprites.
///
/// These are drawn in plain screen space, not dimetric.
class SpritePlainRenderer : SpriteRendererBase
{
private:
    alias GenericSpritePage!(SpriteTypePlain, BinaryTexturePacker) SpritePage;

    // Sprite page whose textures, vertex and index buffer are currently bound.
    //
    // Only matters when drawing.
    SpritePage* boundSpritePage_ = null;

    // Handle to the sprite 2D position uniform.
    uint positionUniformHandle_;

    // Projection matrix of the camera.
    Uniform!mat4 projectionUniform_;

    // Diffuse color texture unit.
    Uniform!int diffuseSamplerUniform_;

    // Minimum bounds of the 2D clipped area. Any pixels outside this area will be discarded.
    Uniform!vec2 minClipBoundsUniform_;
    // Maximum bounds of the 2D clipped area. Any pixels outside this area will be discarded.
    Uniform!vec2 maxClipBoundsUniform_;

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

        uploadUniforms(position);

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

    /// Set 2D area to draw in. Any pixels outside of this area will be discarded.
    @property void clipBounds(const vec2 min, const vec2 max) @safe pure nothrow 
    {
        assert(min.x <= max.x && min.y <= max.y, "Invalid 2D clip bounds");
        minClipBoundsUniform_.value = min;
        maxClipBoundsUniform_.value = max;
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
            projectionUniform_            = Uniform!mat4(getUniformHandle("projection"));
            diffuseSamplerUniform_        = Uniform!int(getUniformHandle("texDiffuse"));
            minClipBoundsUniform_         = Uniform!vec2(getUniformHandle("min2DClipBounds"));
            maxClipBoundsUniform_         = Uniform!vec2(getUniformHandle("max2DClipBounds"));
            positionUniformHandle_        = getUniformHandle("spritePosition2D");

            diffuseSamplerUniform_.value  = SpriteTextureUnit.Diffuse;
            minClipBoundsUniform_.value   = vec2(-100000.0f, -100000.0f);
            maxClipBoundsUniform_.value   = vec2(100000.0f,  100000.0f);
        }
    }

    override void resetUniforms() @safe pure nothrow
    {
        diffuseSamplerUniform_.reset();
        minClipBoundsUniform_.reset();
        maxClipBoundsUniform_.reset();
    }

private:
    // Upload uniforms that need to be uploaded before drawing.
    //
    // Params:  position = 2D position of the bottom-left corner of the sprite.
    void uploadUniforms(const vec2 position)
    {
        // The uniforms encapsulated in Uniform structs don't have to be reuploaded every time.

        projectionUniform_.uploadIfNeeded(spriteShader_);
        diffuseSamplerUniform_.uploadIfNeeded(spriteShader_);
        minClipBoundsUniform_.uploadIfNeeded(spriteShader_);
        maxClipBoundsUniform_.uploadIfNeeded(spriteShader_);
        // Reuploaded for each sprite.
        with(*spriteShader_)
        {
            setUniform(positionUniformHandle_, position);
        }
    }
}
