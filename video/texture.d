
//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// 2D texture.
module video.texture;


import gl3n.linalg;

import video.gl2texture;


/// 2D texture.
///
/// Constructed by Renderer.createTexture().
struct Texture
{
package:
    union 
    {
        // Data members for the GL2 backend.
        GL2TextureData gl2_;
    }

    // X and Y size of the texture in pixels.
    vec2u dimensions_;

    // Alias for readability.
    alias Texture Self;

    // Pointer to the destructor implementation.
    void function(ref Self)             dtor_;
    // Pointer to the bind implementation.
    void function(ref Self, const uint) bind_;

public:
    /// Destroy the Texture, freeing any resources used.
    ~this()
    {
        dtor_(this);
    }

    /// Get the dimensions of the texture in pixels.
    @property vec2u dimensions() @safe const pure nothrow {return dimensions_;}

    /// Bind the texture to specified texture unit (to be used for drawing).
    ///
    /// If textureUnit is greater than the maximum texture unit
    /// supported on the machine, it will be silently ignored.
    /// You can determine the number of texture units supported by
    /// calling Renderer.textureUnitCount. It must always be at least 2.
    void bind(const uint textureUnit = 0)
    {
        bind_(this, textureUnit);
    }
}


