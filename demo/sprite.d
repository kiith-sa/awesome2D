//          Copyright Ferdinand Majerech 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// A sprite supporting 3D position and rotation but using 2D graphics.
module demo.sprite;


import std.algorithm;
import std.exception;
import std.math;
import std.string;

import dgamevfs._;
import gl3n.aabb;
import gl3n.linalg;

import color;
import demo.camera2d;
import demo.light;
import formats.image;
import image;
import math.math;
import memory.memory;
import video.exceptions;
import video.glslshader;
import video.renderer;
import video.texture;
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
struct Sprite
{
private:
    // Vertex type used by sprite vertex buffers.
    struct SpriteVertex
    {
        // Position of the vertex.
        vec2 position;
        // Texture coordinate of the vertex.
        vec2 texCoord;

        // Metadata for Renderer.
        mixin VertexAttributes!(vec2, AttributeInterpretation.Position,
                                vec2, AttributeInterpretation.TexCoord);
    }

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
        /// Rotation of the sprite around the Z axis in radians.
        ///
        /// If the sprite is drawn with this (or close) rotation, this frame will be used.
        float zRotation;
        /// Diffuse color texture layer of the sprite.
        Texture* diffuse;
        /// Normal direction texture layer of the sprite.
        ///
        /// If not null, offset must also be non-null.
        Texture* normal;
        /// Position offset texture layer of the sprite.
        ///
        /// Colors of this texture represent positions within the sprite's bounding box.
        /// R is the X coordinate, G is Y, and B is Z. The minimum value 
        /// (0) maps to the minimum value of the coordinate in the bounding box,
        /// while the maximum (255 or 1.0) is the maximum value.
        ///
        /// If not null, normal must also be non-null.
        Texture* offset;

        /// Is the facing validly initialized (i.e. an does its invariant hold?)?
        @property bool isValid() const pure nothrow 
        {
            return !isNaN(zRotation) &&
                   diffuse !is null &&
                   ((normal is null) == (offset is null));
        }
    }

    // Manually allocated array of facings.
    Facing[] facings_;

    // Name of the sprite, used for debugging.
    string name_;

    // Vertex buffer used to draw the sprite. Stores two triangles.
    VertexBuffer!SpriteVertex* vertexBuffer_;

public:
    /// Construct a Sprite.
    ///
    /// Params:  renderer  = Renderer to create textures.
    ///          spriteDir = Directory to load images of the sprite from.
    ///          yaml      = YAML node to load sprite metadata from.
    ///          name      = Name of the sprite used for debugging.
    this(Renderer renderer, VFSDir spriteDir, ref YAMLNode yaml, string name)
    {
        name_ = name;

        // Load texture with specified filename from spriteDir.
        Texture* loadTexture(string filename)
        {
            auto file = spriteDir.file(filename);
            enforce(file.exists,
                    new SpriteInitException("Sprite image " ~ filename ~ " does not exist."));
            try
            {
                // Read from file and ensure image size matches the sprite size.
                Image textureImage;
                readImage(textureImage, file);
                textureImage.flipVertical();
                enforce(textureImage.size == size_,
                        new SpriteInitException(
                            format("Size %s of image %s in sprite %s does not match the " ~ 
                                   "sprite (%s).", textureImage.size, filename, name, size_)));

                // Load a texture from the image.
                const params = TextureParams().filtering(TextureFiltering.Nearest);
                auto result = renderer.createTexture(textureImage, params);
                enforce(result !is null,
                        new SpriteInitException
                        ("Sprite texture could not be created from image " ~ filename ~ "."));
                return result;
            }
            catch(VFSException e)
            {
                throw new SpriteInitException("Couldn't read image " ~ filename ~ ": " ~ e.msg);
            }
            catch(ImageFileException e)
            {
                throw new SpriteInitException("Couldn't read image " ~ filename ~ ": " ~ e.msg);
            }
        }

        try
        {
            // Load sprite metadata.
            auto spriteMeta = yaml["sprite"];
            size_ = fromYAML!vec2u(spriteMeta["size"], "sprite size");
            const offsetScale =
                fromYAML!float(spriteMeta["offsetScale"], "sprite offset scale");
            auto posExtents = spriteMeta["posExtents"];
            boundingBox_ = AABB(offsetScale * fromYAML!vec3(posExtents["min"]), 
                                offsetScale * fromYAML!vec3(posExtents["max"]));

            // Load data for each facing ("image") in the sprite.
            auto images = yaml["images"];
            enforce(images.length > 0,
                    new SpriteInitException("Sprite with no images"));
            facings_ = allocArray!Facing(images.length);
            scope(failure)
            {
                // The loading might fail half-way; free everything that was
                // loaded in that case.
                free(facings_);
                foreach(ref facing; facings_)
                {
                    if(facing.diffuse !is null){free(facing.diffuse);}
                    if(facing.normal !is null){free(facing.normal);}
                    if(facing.offset !is null){free(facing.offset);}
                }
            }
            uint i = 0;
            // Every "image" in metadata refers to a facing with multiple layers.
            foreach(ref YAMLNode image; images) with(facings_[i])
            {
                // Need to convert from degrees to radians.
                zRotation = fromYAML!float(image["zRotation"], "Sprite image rotation")
                            * (PI / 180.0);
                auto layers = image["layers"];
                // Load textures for the facing.
                diffuse = loadTexture(layers["diffuse"].as!string);
                normal  = loadTexture(layers["normal"].as!string);
                offset  = loadTexture(layers["offset"].as!string);
                enforce(isValid,
                        new SpriteInitException("Invalid image in sprite " ~ name));
                ++i;
            }
        }
        catch(YAMLException e)
        {
            throw new SpriteInitException
                ("Failed to initialize sprite " ~ name_ ~ ": " ~ e.msg);
        }

        vertexBuffer_ = renderer.createVertexBuffer!SpriteVertex(PrimitiveType.Triangles);
        alias SpriteVertex V;
        // Using integer division to make sure we end up on a whole-pixel boundary
        // (avoids blurriness).
        vec2 min = vec2(-(cast(int)size_.x / 2), -(cast(int)size_.y / 2));
        vec2 max = min + vec2(size_);
        // 2 triangles forming a quad.
        vertexBuffer_.addVertex(V(min,                vec2(0.0f, 0.0f)));
        vertexBuffer_.addVertex(V(max,                vec2(1.0f, 1.0f)));
        vertexBuffer_.addVertex(V(vec2(min.x, max.y), vec2(0.0f, 1.0f)));
        vertexBuffer_.addVertex(V(max,                vec2(1.0f, 1.0f)));
        vertexBuffer_.addVertex(V(min,                vec2(0.0f, 0.0f)));
        vertexBuffer_.addVertex(V(vec2(max.x, min.y), vec2(1.0f, 0.0f)));
        vertexBuffer_.lock();
    }

    /// Destroy the sprite, freeing used textures.
    ~this()
    {
        // Don't try to delete facings if initialization failed.
        if(facings_ !is null)
        {
            foreach(ref facing; facings_)
            {
                assert(facing.isValid, "Invalid sprite facing at destruction");
                free(facing.diffuse);
                free(facing.normal);
                free(facing.offset);
            }
            free(facings_);
        }
        if(vertexBuffer_ !is null)
        {
            free(vertexBuffer_);
        }
    }

    /// Return size of the sprite in pixels.
    @property vec2u size() const pure nothrow {return size_;}

private:
    /// Get a pointer to the facing of the sprite closest to specified rotation value.
    Facing* closestFacing(vec3 rotation)
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
        Facing* closest = &(facings_[0]);
        foreach(ref facing; facings_)
        {
            const difference = abs(facing.zRotation - rotation.z);
            if(difference < minDifference)
            {
                minDifference = difference;
                closest = &facing;
            }
        }
        return closest;
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

/// Manages rendering of sprites with lighting.
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

    // Vertical angle of the view.
    float verticalAngle_;

    // Are we currently drawing sprites? If true, spriteShader_ is bound.
    bool drawing_;

    // Shader program used to draw sprites. The lighting model is implemented on shader.
    GLSLShaderProgram* spriteShader_;

    // Handle to the sprite 3D position uniform.
    uint positionUniform_;
    // Handle to the vertical view angle uniform.
    uint verticalAngleUniform_;
    // Handle to the projection matrix uniform.
    uint projectionUniform_;

    // Handle to the uniform setting which texture unit the diffuse color texture is on.
    uint diffuseSamplerUniform_;
    // Handle to the uniform setting which texture unit the normal texture is on.
    uint normalSamplerUniform_;
    // Handle to the uniform setting which texture unit the offset texture is on.
    uint offsetSamplerUniform_;

    // Handle to the minimum offset bounds uniform.
    uint minBoundsUniform_;
    // Handle to the maximum offset bounds uniform.
    uint maxBoundsUniform_;

    // Handle to the ambient light color uniform.
    uint ambientLightUniform_;

    // Handle to the directional light directions array uniform.
    uint directionalDirectionsUniform_;
    // Handle to the directional light diffuse colors array uniform.
    uint directionalDiffuseUniform_;

    // Handle to the point light positions array uniform.
    uint pointPositionsUniform_;
    // Handle to the point light diffuse colors array uniform.
    uint pointDiffuseUniform_;
    // Handle to the point light attenuations array uniform.
    uint pointAttenuationsUniform_;

    // Reference to the camera used to set up the projection matrix.
    Camera2D camera_;

    // Color of the ambient light.
    vec3 ambientLight_ = vec3(0.0f, 0.0f, 0.0f);

    // Number of directional light pointers currently stored in directionalLights_.
    uint directionalLightsUsed_ = 0;
    // Pointers to registered directional lights. Fixed size as the maximum number 
    // of directional lights is known at compile time. Only the first 
    // directionalLightsUsed_ elements are valid.
    const(DirectionalLight)*[maxDirectionalLights] directionalLights_;
    // Storage to copy directional light directions to before being uploaded as uniforms.
    vec3[maxDirectionalLights] directionalDirections_;
    // Storage to copy directional light diffuse colors to before being uploaded as uniforms.
    vec3[maxDirectionalLights] directionalDiffuse_;

    // Number of point light pointers currently stored in pointLights_.
    uint pointLightsUsed_ = 0;
    // Pointers to registered point lights. Fixed size as the maximum number 
    // of point lights is known at compile time. Only the first 
    // pointLightsUsed_ elements are valid.
    const(PointLight)*[maxPointLights] pointLights_;
    // Storage to copy point light positions to before being uploaded as uniforms.
    vec3[maxPointLights] pointPositions_;
    // Storage to copy point light diffuse colors to before being uploaded as uniforms.
    vec3[maxPointLights] pointDiffuse_;
    // Storage to copy point light attenuations to before being uploaded as uniforms.
    float[maxPointLights] pointAttenuations_;

public:
    /// Construct a SpriteRenderer.
    ///
    /// Params:  renderer      = Renderer used for graphics functionality.
    ///          dataDir       = Data directory (must contain a "shaders" subdirectory
    ///                          to load shaders from).
    ///          verticalAngle = Vertical view angle.
    ///          camera        = Reference to the camera used for viewing.
    this(Renderer renderer, VFSDir dataDir, 
         float verticalAngle, Camera2D camera)
    {
        renderer_      = renderer;
        camera_        = camera;
        verticalAngle_ = verticalAngle * degToRad;
        spriteShader_  = renderer.createGLSLShader();
        try
        {
            // Load the shader.
            auto shaderDir = dataDir.dir("shaders");
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

            // Get handles to access uniforms with.
            with(*spriteShader_)
            {
                positionUniform_              = getUniformHandle("spritePosition3D");
                verticalAngleUniform_         = getUniformHandle("verticalAngle");
                projectionUniform_            = getUniformHandle("projection");
                diffuseSamplerUniform_        = getUniformHandle("texDiffuse");
                normalSamplerUniform_         = getUniformHandle("texNormal");
                offsetSamplerUniform_         = getUniformHandle("texOffset");
                minBoundsUniform_             = getUniformHandle("minBounds");
                maxBoundsUniform_             = getUniformHandle("maxBounds");
                directionalDirectionsUniform_ = getUniformHandle("directionalDirections");
                directionalDiffuseUniform_    = getUniformHandle("directionalDiffuse");
                pointPositionsUniform_        = getUniformHandle("pointPositions");
                pointDiffuseUniform_          = getUniformHandle("pointDiffuse");
                pointAttenuationsUniform_     = getUniformHandle("pointAttenuations");
                ambientLightUniform_          = getUniformHandle("ambientLight");
            }
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

    /// Destroy the SpriteRenderer, freeing all used resources.
    ///
    /// Must be called as SpriteRenderer uses manually allocated memory.
    ~this()
    {
        free(spriteShader_);
    }

    /// Start drawing sprites.
    ///
    /// Must be called before any calls to drawSprite().
    ///
    /// Binds SpriteRenderer's sprite shader. No other shader can be bound until 
    /// stopDrawing() is called.
    void startDrawing()
    {
        assert(!drawing_, "SpriteRenderer.startDrawing() called when already drawing");
        drawing_ = true;
        spriteShader_.bind();
    }

    /// Stop drawing sprites.
    ///
    /// Must be called after drawing sprites to allow other drawing operations.
    ///
    /// Releases SpriteRenderer's sprite shader, allowing other shaders to be bound.
    void stopDrawing()
    {
        assert(drawing_, "SpriteRenderer.stopDrawing() called without calling startDrawing()");
        spriteShader_.release();
        drawing_ = false;
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
    void drawSprite(Sprite* sprite, vec3 position, const vec3 rotation)
    {
        assert(drawing_, "SpriteRenderer.drawSprite() called without calling startDrawing()");
        // Get on a whole-pixel boundary to avoid blurriness.
        position.x = cast(int)(position.x);
        position.y = cast(int)(position.y);

        // This might end up being too slow.
        //
        // In that case, we'll need to update this and upload uniforms only
        // when lights are added or removed, or when their parameters change.
        updateDirectionalUniforms();
        updatePointUniforms();

        // Upload the uniforms.

        // Again; this will probably be too slow. 
        // We need to only upload data when it changes. 
        // Positions and bounds change per-sprite, but the vertical angle, projection,
        // and light data change only from time to time.
        with(*spriteShader_)
        {
            // View angle and projection.
            setUniform(verticalAngleUniform_,  verticalAngle_);
            setUniform(projectionUniform_,     camera_.projection);

            // Sprite position and bounds.
            setUniform(positionUniform_,       position);
            setUniform(minBoundsUniform_,      sprite.boundingBox_.min);
            setUniform(maxBoundsUniform_,      sprite.boundingBox_.max);

            // Texture units used by specified textures.
            setUniform(diffuseSamplerUniform_, 0);
            setUniform(normalSamplerUniform_,  1);
            setUniform(offsetSamplerUniform_,  2);

            // Lighting parameters.
            setUniform(ambientLightUniform_,               ambientLight_);
            // We pass each light attribute as a separate array as there is no
            // way to pass struct arrays to shaders (at least with GL 2.1).
            setUniformArray(directionalDirectionsUniform_, directionalDirections_);
            setUniformArray(directionalDiffuseUniform_,    directionalDiffuse_);
            setUniformArray(pointPositionsUniform_,        pointPositions_);
            setUniformArray(pointDiffuseUniform_,          pointDiffuse_);
            setUniformArray(pointAttenuationsUniform_,     pointAttenuations_);
        }

        Sprite.Facing* facing = sprite.closestFacing(rotation);
        facing.diffuse.bind(0);
        facing.normal.bind(1);
        facing.offset.bind(2);
        renderer_.drawVertexBuffer(sprite.vertexBuffer_, null, spriteShader_);
    }

    /// Set the ambient light color.
    @property void ambientLight(const vec3 rhs) pure nothrow {ambientLight_ = rhs;}

    /// Register a directional (infinite-distance) light, and use it in future sprite draws.
    ///
    /// Useful for light sources with "parallel" rays such as the sun.
    ///
    /// Note: Number of directional lights that may be registered simultaneously.
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
    }

    /// Unregister a directional light so it's not used in future sprite draws.
    ///
    /// Params:  light = Pointer to the light to unregister. Must be a pointer
    ///                  to one of currently registered lights.
    void unregisterDirectionalLight(const(DirectionalLight)* light) @safe pure nothrow
    {
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

    /// Register a point light, and use it in future sprite draws.
    ///
    /// Useful for light sources such as lamps, explosions and so on.
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
    }

    /// Unregister a point light so it's not used in future sprite draws.
    ///
    /// Params:  light = Pointer to the light to unregister. Must be a pointer
    ///                  to one of currently registered lights.
    void unregisterPointLight(const(PointLight)* light) @safe pure nothrow
    {
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
            directionalDirections_[l] = directionalLights_[l].direction;
            const color = directionalLights_[l].diffuse;
            directionalDiffuse_[l] = vec3(color.r / 255.0f, color.g / 255.0f, color.b / 255.0f);
        }
        // Due to optimization, the shader always processes all lights,
        // including those that are unspecified, so we specify data that
        // will result in no effect (black color, etc.).
        directionalDirections_[directionalLightsUsed_ .. $] = vec3(0.0, 0.0, 1.0);
        directionalDiffuse_[directionalLightsUsed_ .. $]    = vec3(0.0, 0.0, 0.0);
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
            pointPositions_[l]    = pointLights_[l].position;
            const color           = pointLights_[l].diffuse;
            pointDiffuse_[l]      = vec3(color.r / 255.0f, color.g / 255.0f, color.b / 255.0f);
            pointAttenuations_[l] = pointLights_[l].attenuation;
        }
        // Due to optimization, the shader always processes all lights,
        // including those that are unspecified, so we specify data that
        // will result in no effect (black color, etc.).
        pointPositions_[pointLightsUsed_ .. $]    = vec3(0.0, 0.0, 0.0);
        pointDiffuse_[pointLightsUsed_ .. $]      = vec3(0.0, 0.0, 0.0);
        pointAttenuations_[pointLightsUsed_ .. $] = 1.0f;
    }
}
