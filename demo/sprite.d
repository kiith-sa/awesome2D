//          Copyright Ferdinand Majerech 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// A sprite supporting 3D position and rotation but using 2D graphics.
module demo.sprite;


import std.exception;
import std.math;
import std.string;

import dgamevfs._;
import gl3n.aabb;
import gl3n.linalg;

import formats.image;
import image;
import memory.memory;
import video.renderer;
import video.texture;
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
                enforce(textureImage.size == size_,
                        new SpriteInitException(
                            format("Size %s of image %s in sprite %s does not match the " ~ 
                                   "sprite (%s).", textureImage.size, filename, name, size_)));

                // Load a texture from the image.
                auto result = renderer.createTexture(textureImage);
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
            auto posExtents = spriteMeta["posExtents"];
            boundingBox_ = AABB(fromYAML!vec3(posExtents["min"]), 
                                fromYAML!vec3(posExtents["max"]));

            // Load data for each facing ("image") in the sprite.
            auto images = yaml["images"];
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
            foreach(ref YAMLNode image; images) with(facings_[i])
            {
                // Need to convert from degrees to radians.
                zRotation = fromYAML!float(image["zRotation"], "Sprite image rotation")
                            * (PI / 180.0);
                // Load textures for the facing.
                diffuse = loadTexture(image["diffuse"].as!string);
                normal = image.containsKey("normal") 
                         ? loadTexture(image["normal"].as!string) : null;
                offset = image.containsKey("offset") 
                         ? loadTexture(image["offset"].as!string) : null;
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
                if(facing.normal !is null)
                {
                    free(facing.normal);
                    free(facing.offset);
                }
            }
            free(facings_);
        }
    }
}
