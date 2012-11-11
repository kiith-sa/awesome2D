//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// GL2 2D texture backend.
module video.gl2texture;


import derelict.opengl.gl;
import image;
import video.texture;


package:

/// Construct a GL2 texture backend with specified parameters from specified image.
void constructTextureGL2
    (ref Texture texture, ref const Image image, const ref TextureParams params)
{
    texture.gl2_        = GL2TextureData.init;
    texture.dimensions_ = image.size();
    texture.params_     = params;
    //TODO
}

/// Data members of the GL2 texture backend.
struct GL2TextureData
{
    GLuint textureHandle_;
}
