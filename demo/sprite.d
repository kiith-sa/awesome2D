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

        /// Get the lower bound of number of bytes taken by this struct in RAM (not VRAM).
        @property size_t memoryBytes() @safe const pure nothrow 
        {
            return this.sizeof + 
                   diffuse.memoryBytes + normal.memoryBytes + offset.memoryBytes;
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
    ///
    /// Throws:  SpriteInitException on failure (e.g. if one of the sprite's
    ///          images could not be read).
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
                facings_ = null;
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

    /// Return a reference to the bounding box of the sprite.
    @property ref const(AABB) boundingBox() const pure nothrow {return boundingBox_;}

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

    /// Get the lower bound of number of bytes taken by this struct in RAM (not VRAM).
    @property size_t memoryBytes() @trusted const
    {
        return this.sizeof + name_.length + vertexBuffer_.memoryBytes +
               facings_.map!((ref const Facing t) => t.memoryBytes).reduce!"a + b";
    }
}

/// A convenience function to load a Sprite, handling possible errors.
///
/// Params:  renderer = Renderer to create textures.
///          gameDir  = Game data directory.
///          name     = Name of the subdirectory of gameDir containing the sprite images and 
///                     metadata file (sprite.yaml).
///
/// Returns: Pointer to the sprite on success, null on failure.
Sprite* loadSprite(Renderer renderer, VFSDir gameDir, string name)
{
    try
    {
        auto spriteDir = gameDir.dir(name);
        auto spriteMeta = loadYAML(spriteDir.file("sprite.yaml"));
        return alloc!Sprite(renderer, spriteDir, spriteMeta, name);
    }
    catch(VFSException e)
    {
        writeln("Filesystem error loading sprite \"", name, "\" : ", e.msg);
        return null;
    }
    catch(YAMLException e)
    {
        writeln("YAML error loading sprite \"", name, "\" : ", e.msg);
        return null;
    }
    catch(SpriteInitException e)
    {
        writeln("Sprite initialization error loading sprite \"", name, "\" : ", e.msg);
        return null;
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

    /// Convenience wrapper for a GLSL uniform variable or array.
    ///
    /// Allows to only reupload the uniform after it is modified.
    struct Uniform(Type)
    {
        private:
            // Value of the uniform variable/array.
            Type value_;
            // Handle to the uniform in a GLSLShaderProgram.
            uint handle_;
            // Do we need to reupload the uniform? (e.g. after modification).
            bool needReupload_ = true;

        public:
            /// Construct a Uniform with specified handle.
            this(const uint handle) @safe pure nothrow
            {
                handle_ = handle;
            }

            /// Set the uniform's value.
            @property void value(const Type rhs) @safe pure nothrow 
            {
                value_ = rhs;
                needReupload_ = true;
            }

            /// Ditto.
            @property void value(ref const Type rhs) @safe pure nothrow 
            {
                value_ = rhs;
                needReupload_ = true;
            }

            /// Force the uniform to be uploaded before the next draw.
            ///
            /// Should be called after a shader is bound to ensure the uniforms are uploaded.
            void reset() @safe pure nothrow
            {
                needReupload_ = true;
            }

            /// Upload the uniform to passed shader if its value has changed or it's been reset.
            ///
            /// Params:  shader = Shader this uniform belongs to. Must be the shader
            ///                   that was used to determine the uniform's handle.
            void uploadIfNeeded(GLSLShaderProgram* shader)
            {
                if(!needReupload_) {return;}
                static if(isStaticArray!Type)
                {
                    shader.setUniformArray(handle_, value_);
                }
                else
                {
                    shader.setUniform(handle_, value_);
                }
                needReupload_ = false;
            }
    }

    // Renderer used for drawing.
    Renderer renderer_;

    // Are we currently drawing sprites? If true, spriteShader_ is bound.
    bool drawing_;

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
         float verticalAngle, Camera2D camera)
    {
        renderer_                      = renderer;
        camera_                        = camera;
        spriteShader_                  = renderer.createGLSLShader();
        directionalUniformsNeedUpdate_ = true;
        pointUniformsNeedUpdate_       = true;
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

                verticalAngleUniform_.value   = verticalAngle * degToRad;
                diffuseSamplerUniform_.value  = 0;
                normalSamplerUniform_.value   = 1;
                offsetSamplerUniform_.value   = 2;
                ambientLightUniform_.value    = vec3(0.0f, 0.0f, 0.0f);
                minClipBoundsUniform_.value   = vec3(-100000.0f, -100000.0f, -100000.0f);
                maxClipBoundsUniform_.value   = vec3(100000.0f,  100000.0f, 100000.0f);

                positionUniformHandle_        = getUniformHandle("spritePosition3D");
                minOffsetBoundsUniformHandle_ = getUniformHandle("minOffsetBounds");
                maxOffsetBoundsUniformHandle_ = getUniformHandle("maxOffsetBounds");
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
    /// Binds SpriteRenderer's sprite shader, and enables alpha blending.
    /// No other shader can be bound until stopDrawing() is called, 
    /// and if alpha blending is disabled between sprite draws, it must be reenabled 
    /// before the next sprite draw.
    ///
    /// This is also the point when camera state is passed to the shader. While drawing,
    /// changes to the camera will have no effect.
    void startDrawing()
    {
        assert(!drawing_, "SpriteRenderer.startDrawing() called when already drawing");
        drawing_ = true;
        renderer_.pushBlendMode(BlendMode.Alpha);
        projectionUniform_.value = camera_.projection;
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
        assert(renderer_.blendMode == BlendMode.Alpha,
               "Non-alpha blend mode before stopping sprite drawing");

        spriteShader_.release();
        renderer_.popBlendMode();
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
        assert(renderer_.blendMode == BlendMode.Alpha,
               "Non-alpha blend mode when drawing a sprite");
        // Get on a whole-pixel boundary to avoid blurriness.
        position.x = cast(int)(position.x);
        position.y = cast(int)(position.y);

        if(directionalUniformsNeedUpdate_) {updateDirectionalUniforms();}
        if(pointUniformsNeedUpdate_)       {updatePointUniforms();}

        // Upload the uniforms.

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

        Sprite.Facing* facing = sprite.closestFacing(rotation);
        facing.diffuse.bind(0);
        facing.normal.bind(1);
        facing.offset.bind(2);
        renderer_.drawVertexBuffer(sprite.vertexBuffer_, null, spriteShader_);
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
    void directionalLightsChanged()
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
    void pointLightsChanged()
    {
        pointUniformsNeedUpdate_ = true;
    }

private:
    /// Update data to upload as directional light uniforms.
    void updateDirectionalUniforms() @safe pure nothrow
    {
        // Directly accessing value_ of a Uniform for speed.

        // This will probably need optimization (but need a stress test first).
        //
        // Currently we just overwrite all data but much of it could be retained
        // as lights are not always modified.
        foreach(l; 0 .. directionalLightsUsed_)
        {
            directionalDirectionsUniform_.value_[l] = directionalLights_[l].direction;
            const color = directionalLights_[l].diffuse;
            directionalDiffuseUniform_.value_[l] =
                vec3(color.r / 255.0f, color.g / 255.0f, color.b / 255.0f);
        }
        // Due to optimization, the shader always processes all lights,
        // including those that are unspecified, so we specify data that
        // will result in no effect (black color, etc.).
        directionalDirectionsUniform_.value_[directionalLightsUsed_ .. $] = vec3(0.0, 0.0, 1.0);
        directionalDiffuseUniform_.value_[directionalLightsUsed_ .. $]    = vec3(0.0, 0.0, 0.0);

        // Force reupload.
        directionalDirectionsUniform_.reset();
        directionalDiffuseUniform_.reset();

        directionalUniformsNeedUpdate_ = false;
    }

    /// Update data to upload as point light uniforms.
    void updatePointUniforms() @safe pure nothrow
    {
        // Directly accessing value_ of a Uniform for speed.

        // This will probably need optimization (but need a stress test first).
        //
        // Currently we just overwrite all data but much of it could be retained
        // as lights are not always modified.
        foreach(l; 0 .. pointLightsUsed_)
        {
            const color           = pointLights_[l].diffuse;
            const colorNormalized = vec3(color.r / 255.0f, color.g / 255.0f, color.b / 255.0f);

            pointPositionsUniform_.value_[l]    = pointLights_[l].position;
            pointDiffuseUniform_.value_[l]      = colorNormalized;
            pointAttenuationsUniform_.value_[l] = pointLights_[l].attenuation;
        }
        // Due to optimization, the shader always processes all lights,
        // including those that are unspecified, so we specify data that
        // will result in no effect (black color, etc.).
        pointPositionsUniform_.value_[pointLightsUsed_ .. $]    = vec3(0.0, 0.0, 0.0);
        pointDiffuseUniform_.value_[pointLightsUsed_ .. $]      = vec3(0.0, 0.0, 0.0);
        pointAttenuationsUniform_.value_[pointLightsUsed_ .. $] = 1.0f;

        // Force reupload.
        pointPositionsUniform_.reset();
        pointDiffuseUniform_.reset();
        pointAttenuationsUniform_.reset();

        pointUniformsNeedUpdate_ = false;
    }
}
