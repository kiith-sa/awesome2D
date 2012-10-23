
//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// GLSL shader program.
module video.glslshader;


/// Shader program implemented in the GLSL language.
struct GLSLShader
{
    //"Derived" implementations will override API function pointers.
    // TODO:
    // Access uniforms by handles, not names. We should make it convenient
    // with a mixin struct storing the handles in named data members.
}

