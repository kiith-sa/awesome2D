//          Copyright Ferdinand Majerech 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// A sprite supporting 3D position and rotation but using 2D graphics.
module demo.sprite;


import std.algorithm;
import std.exception;
import std.math;
import std.stdio;
import std.string;

import dgamevfs._;
import gl3n.aabb;
import gl3n.linalg;

import color;
import demo.camera2d;
import demo.light;
import demo.spritemanager;
import demo.spritepage;
import demo.spritevertex;
import demo.texturepacker;
import formats.image;
import image;
import math.math;
import memory.memory;
import video.exceptions;
import video.indexbuffer;
import video.glslshader;
import video.renderer;
import video.texture;
import video.uniform;
import video.vertexbuffer;
import util.yaml;


/// Exception throws when a sprite fails to initialize.
class SpriteInitException : Exception 
{
    public this(string msg, string file = __FILE__, int line = __LINE__)
    {
        super(msg, file, line);
    }
}

/// A sprite supporting 3D position and rotation but using 2D graphics.
///
/// Composed of multiple images (different image for each facing).
///
/// Sprites are created by a SpriteManager and must be deleted 
/// by free() before the SpriteManager used to create them is destroyed.
struct Sprite
{
package:
    // Size of the sprite in pixels.
    vec2u size_;

    // Bounding box of the sprite. 
    //
    // Used by offset textures, where the minimum value for each color matches
    // the minimum value of the corresponding coordinate in the bounding box,
    // and analogously with maximum.
    AABB boundingBox_;

    // Single image of the sprite representing one direction the sprite can face.
    struct Facing
    {
        // Texture area taken up by the facing's image on its sprite page.
        TextureArea textureArea;
        // Pointer to the sprite page this facing's image is packed into.
        SpritePage* spritePage;
        // Rotation of the sprite around the Z axis in radians.
        //
        // If the sprite is drawn with this (or close) rotation, this frame will be used.
        float zRotation;
        // Offset into the index buffer of the texture page where the first 
        // index used to draw the facing's image can be found.
        uint indexBufferOffset = uint.max;

        // Is the facing validly initialized (i.e. an does its invariant hold?)?
        @property bool isValid() const pure nothrow 
        {
            return !isNaN(zRotation) && textureArea.valid && 
                   spritePage !is null && indexBufferOffset != uint.max;
        }

        // Get the lower bound of number of bytes taken by this struct in RAM (not VRAM).
        @property size_t memoryBytes() @safe const pure nothrow 
        {
            return this.sizeof;
        }
    }

    // Manually allocated array of facings.
    Facing[] facings_;

    // Name of the sprite, used for debugging.
    string name_;

    // Sprite manager that was used to create this sprite.
    SpriteManager manager_;

public:
    /// Destroy the sprite.
    ///
    /// The sprite must be destroyed before the SpriteManager used to create it.
    ~this()
    {
        // Don't try to delete facings if initialization failed.
        if(facings_ !is null)
        {
            assert(manager_ !is null,
                   "Sprite is initialized, but its SpriteManager is not set");

            foreach(ref facing; facings_)
            {
                assert(facing.isValid, "Invalid sprite facing at destruction");
                facing.spritePage.removeImage(facing.textureArea,
                                              facing.indexBufferOffset);
            }
            free(facings_);
            manager_.spriteDeleted(&this);
            return;
        }
        assert(manager_ is null, "Partially initialized sprite");
    }

    /// Return size of the sprite in pixels.
    @property vec2u size() const pure nothrow {return size_;}

    /// Get the (debugging) name of the sprite.
    @property string name() @safe const pure nothrow {return name_;}

    /// Return a reference to the bounding box of the sprite.
    @property ref const(AABB) boundingBox() @safe const pure nothrow {return boundingBox_;}

    /// Get the index of the facing of the sprite closest to specified rotation value.
    uint closestFacing(vec3 rotation)
    {
        // Will probably need optimization.
        // Linear search _might_ possibly be fast enough though, and having variable 
        // number of facings is useful. 
        //
        // Maybe, if facings read from a file have a specific format 
        // (e.g. N equally separated facings where N is a power of two;
        //  we could assign indices to angles and have a function that would quickly
        //  compute which index given rotation corresponds to)
        rotation.z = rotation.z - 2.0 * PI * floor(rotation.z / (2.0 * PI));
        assert(facings_.length > 0, "A sprite with no facings");
        float minDifference = abs(facings_[0].zRotation - rotation.z);
        uint closest = 0;
        foreach(uint index, ref facing; facings_)
        {
            const difference = abs(facing.zRotation - rotation.z);
            if(difference < minDifference)
            {
                minDifference = difference;
                closest = index;
            }
        }
        return closest;
    }

    /// Get the lower bound of number of bytes taken by this struct in RAM (not VRAM).
    @property size_t memoryBytes() @trusted const
    {
        return this.sizeof + name_.length +
               facings_.map!((ref const Facing t) => t.memoryBytes).reduce!"a + b";
    }
}

/// Exception thrown when SpriteRenderer fails to initialize.
class SpriteRendererInitException : Exception 
{
    public this(string msg, string file = __FILE__, int line = __LINE__)
    {
        super(msg, file, line);
    }
}

/// Manages sprite rendering with lighting.
///
/// Lights can be added and removed (registered and unregistered).
/// Sprites are drawn using drawSprite(). Any sprite draws must happen between 
/// calls to startDrawing() and stopDrawing(). Between these calls, the sprite
/// renderer binds its internal shader used to handle lighting, so on other shader
/// can be bound.
class SpriteRenderer
{
public:
    // Maximum number of directional lights supported.
    //
    // This is hardcoded in the sprite fragment shader. If changed, update the
    // shader as well as any 4's found in documentation/errors in this file.
    enum maxDirectionalLights = 4;

    // Maximum number of point lights supported.
    //
    // This is hardcoded in the sprite fragment shader. If changed, update the
    // shader as well as any 8's found in documentation/errors in this file.
    enum maxPointLights = 8;

private:
    // Renderer used for drawing.
    Renderer renderer_;

    // Are we currently drawing sprites? If true, spriteShader_ is bound.
    bool drawing_;

    // Game data directory (to load shader from).
    VFSDir dataDir_;

    // Vertical view angle.
    float verticalAngle_;

    // Shader program used to draw sprites. The lighting model is implemented on shader.
    GLSLShaderProgram* spriteShader_;

    // Handle to the sprite 3D position uniform.
    uint positionUniformHandle_;
    // Handle to the minimum offset bounds uniform.
    uint minOffsetBoundsUniformHandle_;
    // Handle to the maximum offset bounds uniform.
    uint maxOffsetBoundsUniformHandle_;

    // Vertical angle of the view.
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

    // Reference to the camera used to set up the projection matrix.
    Camera2D camera_;

    // Sprite page whose texture is currently bound. Only matters when drawing.
    SpritePage* boundSpritePage_ = null;

    // Currently bound vertex buffer. Only matters when drawing.
    VertexBuffer!(SpriteVertex)* boundVertexBuffer_ = null;

    // Currently bound index buffer. Only matters when drawing.
    IndexBuffer* boundIndexBuffer_ = null;

public:
    /// Construct a SpriteRenderer.
    ///
    /// Params:  renderer      = Renderer used for graphics functionality.
    ///          dataDir       = Data directory (must contain a "shaders" subdirectory
    ///                          to load shaders from).
    ///          verticalAngle = Vertical view angle.
    ///          camera        = Reference to the camera used for viewing.
    ///
    /// Throws:  SpriteRendererInitException on failure.
    this(Renderer renderer, VFSDir dataDir, 
         const float verticalAngle, Camera2D camera) @trusted
    {
        renderer_      = renderer;
        camera_        = camera;
        dataDir_       = dataDir;
        verticalAngle_ = verticalAngle;
        initializeShader();
    }

    /// Destroy the SpriteRenderer, freeing all used resources.
    ///
    /// Must be called as SpriteRenderer uses manually allocated memory.
    @trusted ~this()
    {
        free(spriteShader_);
    }

    /// Start drawing sprites.
    ///
    /// Must be called before any calls to drawSprite().
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
    /// While drawing, changes to the camera will have no effect.
    void startDrawing() @trusted
    {
        assert(!drawing_, "SpriteRenderer.startDrawing() called when already drawing");
        drawing_ = true;
        renderer_.pushBlendMode(BlendMode.Alpha);
        projectionUniform_.value = camera_.projection;
        resetUniforms();
        spriteShader_.bind();
        boundSpritePage_   = null;
        boundVertexBuffer_ = null;
        boundIndexBuffer_  = null;
    }

    /// Stop drawing sprites.
    ///
    /// Must be called after drawing sprites to allow other drawing operations.
    ///
    /// Releases SpriteRenderer's sprite shader, allowing other shaders to be bound.
    void stopDrawing()
    {
        assert(drawing_, "SpriteRenderer.stopDrawing() called without calling startDrawing()");
        assert(renderer_.blendMode == BlendMode.Alpha,
               "Non-alpha blend mode before stopping sprite drawing");

        spriteShader_.release();
        renderer_.popBlendMode();
        drawing_           = false;
        boundSpritePage_   = null;
        if(boundVertexBuffer_ !is null){boundVertexBuffer_.release();}
        if(boundIndexBuffer_  !is null){boundIndexBuffer_.release();}
        boundVertexBuffer_ = null;
        boundIndexBuffer_  = null;
    }

    /// Draw a 2D sprite at specified 3D position.
    ///
    /// Must be called between calls to startDrawing() and stopDrawing().
    ///
    /// Params:  sprite   = Pointer to the sprite to draw.
    ///          position = Position of the sprite in 3D space. The final 2D position is
    ///                     determined by the vertical angle of the SpriteRenderer.
    ///          rotation = Rotation of the sprite around the X, Y and Z axis.
    ///                     (At the moment, only Z affects the graphics as the sprite format 
    ///                     only supports Z rotation).
    void drawSprite(Sprite* sprite, vec3 position, const vec3 rotation) @trusted
    {
        assert(drawing_, "SpriteRenderer.drawSprite() called without calling startDrawing()");
        assert(renderer_.blendMode == BlendMode.Alpha,
               "Non-alpha blend mode when drawing a sprite");
        // Get on a whole-pixel boundary to avoid blurriness.
        position.x = cast(int)(position.x);
        position.y = cast(int)(position.y);

        if(directionalUniformsNeedUpdate_) {updateDirectionalUniforms();}
        if(pointUniformsNeedUpdate_)       {updatePointUniforms();}

        uploadUniforms(sprite, position);

        const facingIndex = sprite.closestFacing(rotation);
        Sprite.Facing* facing = &(sprite.facings_[facingIndex]);
        SpritePage* page = facing.spritePage;
        // Don't rebind a sprite page if we don't have to.
        if(boundSpritePage_ != page)
        {
            page.bind();
            boundSpritePage_ = page;
        }
        if(boundVertexBuffer_ != page.vertices_)
        {
            if(boundVertexBuffer_ !is null){boundVertexBuffer_.release();}
            page.vertices_.bind();
            boundVertexBuffer_ = page.vertices_;
        }
        if(boundIndexBuffer_ != page.indices_)
        {
            if(boundIndexBuffer_ !is null){boundIndexBuffer_.release();}
            page.indices_.bind();
            boundIndexBuffer_ = page.indices_;
        }

        const indexOffset = facing.indexBufferOffset;
        assert(indexOffset % 6 == 0, "Sprite indices don't form sextuples");
        // Assuming a quadruplet per image, added in same order as the indices.
        // See SpritePage vertex/index buffer code.
        const minVertex = (indexOffset / 6) * 4;
        const maxVertex = minVertex + 3;

        renderer_.drawVertexBuffer(page.vertices_, page.indices_, spriteShader_, 
                                   facing.indexBufferOffset, 6, minVertex, maxVertex);
    }

    /// Set the 3D area to draw in. Any pixels outside of this area will be discarded.
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
    ///       a call to directionalLightsChanged() is needed for the changes to take effect.
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
               "Only 4 directional lights are supported; can't register more.");
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
    /// Note: After any modifications to registered directional lights, 
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
               "Only 8 point lights are supported; can't register more.");
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
            // Swap the last used light with one we're removing. 
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

    /// When replacing the renderer, this must be called before the renderer is destroyed.
    void prepareForRendererChange() @trusted
    {
        assert(!drawing_,
               "Trying to change Renderer while drawing with a SpriteRenderer");
        // Deinit the shader.
        free(spriteShader_);
        renderer_ = null;
    }

    /// When replacing the renderer, this must be called to pass the new renderer.
    ///
    /// This will reload the sprite shader, which might take a while.
    void changeRenderer(Renderer newRenderer) @trusted
    {
        assert(renderer_ is null,
               "changeRenderer() called without prepareForRendererChange()");
        assert(!drawing_,
               "Trying to change Renderer while drawing with a SpriteRenderer");
        // Reload the shader, reset uniforms, init uniform handles.
        renderer_ = newRenderer;
        // Ambient is stored directly in the Uniform struct - need to preserve it 
        // between renderer reloads.
        const previousAmbient = ambientLightUniform_.value;
        initializeShader();
        ambientLight = previousAmbient;
    }

private:
    /// Update data to upload as directional light uniforms.
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
            directionalDiffuseUniform_.value[l] =
                vec3(color.r / 255.0f, color.g / 255.0f, color.b / 255.0f);
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

    /// Update data to upload as point light uniforms.
    void updatePointUniforms() @safe pure nothrow
    {
        // This will probably need optimization (but need a stress test first).
        //
        // Currently we just overwrite all data but much of it could be retained
        // as lights are not always modified.
        foreach(l; 0 .. pointLightsUsed_)
        {
            const color           = pointLights_[l].diffuse;
            const colorNormalized = vec3(color.r / 255.0f, color.g / 255.0f, color.b / 255.0f);

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

    // Initialize the sprite shader and uniforms.
    void initializeShader()
    {
        spriteShader_                  = renderer_.createGLSLShader();
        directionalUniformsNeedUpdate_ = true;
        pointUniformsNeedUpdate_       = true;
        try
        {
            // Load the shader.
            auto shaderDir = dataDir_.dir("shaders");
            auto vertFile  = shaderDir.file("sprite.vert");
            auto fragFile  = shaderDir.file("sprite.frag");
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

    // Initialize handles and default values of uniforms used.
    //
    // Called during construction.
    void initializeUniforms()
    {
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

            verticalAngleUniform_.value   = verticalAngle_ * degToRad;
            diffuseSamplerUniform_.value  = SpriteTextureUnit.Diffuse;
            normalSamplerUniform_.value   = SpriteTextureUnit.Normal;
            offsetSamplerUniform_.value   = SpriteTextureUnit.Offset;
            ambientLightUniform_.value    = vec3(0.0f, 0.0f, 0.0f);
            minClipBoundsUniform_.value   = vec3(-100000.0f, -100000.0f, -100000.0f);
            maxClipBoundsUniform_.value   = vec3(100000.0f,  100000.0f, 100000.0f);

            positionUniformHandle_        = getUniformHandle("spritePosition3D");
            minOffsetBoundsUniformHandle_ = getUniformHandle("minOffsetBounds");
            maxOffsetBoundsUniformHandle_ = getUniformHandle("maxOffsetBounds");
        }
    }

    /// Reset all uniforms, forcing them to be reuploaded at next draw.
    void resetUniforms() @safe pure nothrow
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

    // Upload uniforms that need to be uploaded before drawing.
    //
    // Params:  sprite   = Sprite we're about to draw.
    //          position = 3D position of the sprite.
    void uploadUniforms(Sprite* sprite, const vec3 position)
    {
        // The uniforms encapsulate in Uniform structs don't have to be reuploaded every time.

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

        // Uniforms reuploaded for each sprite.
        with(*spriteShader_)
        {
            // Sprite position and bounds.
            setUniform(positionUniformHandle_,        position);
            setUniform(minOffsetBoundsUniformHandle_, sprite.boundingBox_.min);
            setUniform(maxOffsetBoundsUniformHandle_, sprite.boundingBox_.max);
        }
    }
}
