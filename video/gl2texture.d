//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// GL2 2D texture backend.
module video.gl2texture;


import video.texture;


package:

void constructTextureGL2(ref Texture texture)
{
    texture.gl2_ = GL2TextureData.init;
    //TODO
}

/// Data members of the GL2 texture backend.
struct GL2TextureData
{
    
}
