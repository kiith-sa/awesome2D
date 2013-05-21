//          Copyright Ferdinand Majerech 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// A struct wrapping GLSL uniform variables used for 3D lighting.
module demo.lightuniforms;


import util.linalg;
import video.uniform;
import video.glslshader;


/// Wraps GLSL uniforms used for 3D lighting.
///
/// Gets uniform handles from a shader program passed by the user. The user must also 
/// bind the program before uploading the uniforms.
///
/// Uniforms themselves are directly modified by the code in the "light" package
/// (LightManager), and only uploaded when their values change.
struct LightUniforms
{
    // Maximum number of directional lights supported.
    //
    // This is hardcoded in the sprite fragment shader. If changed, update the
    // shader as well as any 2's found in documentation/errors in this file and
    // LightManager.
    enum maxDirectionalLights = 2;

    // Maximum number of point lights supported.
    //
    // This is hardcoded in the sprite fragment shader. If changed, update the
    // shader as well as any 6's found in documentation/errors in this file and
    // LightManager.
    enum maxPointLights = 6;

private:
    // Shader program containing the uniform variables.
    GLSLShaderProgram* shaderProgram_ = null;

package:
    // Ambient light color.
    Uniform!vec3 ambientLight;

    // We pass every light attribute as a separate array as there is no
    // way to pass struct arrays to shaders (at least with GL 2.1).

    // Directions of currently enabled directional lights.
    Uniform!(vec3[maxDirectionalLights]) directionalDirection;
    // Diffuse colors of currently enabled directional lights.
    Uniform!(vec3[maxDirectionalLights]) directionalDiffuse;

    // Positions of currently enabled point lights.
    Uniform!(vec3[maxPointLights]) pointPositions;
    // Diffuse colors of currently enabled point lights.
    Uniform!(vec3[maxPointLights]) pointDiffuse;
    // Attenuations of currently enabled point lights.
    Uniform!(float[maxPointLights]) pointAttenuations;

public:
    /// Use specified shader program, and $(B clear) all uniform values to defaults.
    ///
    /// Generally this should only be changed when the renderer is replaced.
    ///
    /// The shader program must contain these uniform variables:
    ///
    /// vec3 ambientLight
    ///
    /// vec3[maxDirectionalLights] directionalDirections,
    /// vec3[maxDirectionalLights] directionalDiffuse
    ///
    /// vec3[maxPointLights] pointPositions,
    /// vec3[maxPointLights] pointDiffuse.
    /// float[maxPointLights] pointAttenuations
    void useProgram(GLSLShaderProgram* program)
    {
        shaderProgram_ = program;
        with(*shaderProgram_)
        {
            ambientLight         = Uniform!vec3(getUniformHandle("ambientLight"));
            directionalDirection = Uniform!(vec3[maxDirectionalLights]) 
                                                (getUniformHandle("directionalDirections"));
            directionalDiffuse   = Uniform!(vec3[maxDirectionalLights])
                                               (getUniformHandle("directionalDiffuse"));
            pointPositions       = Uniform!(vec3[maxPointLights])
                                               (getUniformHandle("pointPositions"));
            pointDiffuse         = Uniform!(vec3[maxPointLights])
                                               (getUniformHandle("pointDiffuse"));
            pointAttenuations    = Uniform!(float[maxPointLights])
                                                (getUniformHandle("pointAttenuations"));
        }
    }

    /// Upload the uniforms to the shader program previously specified by useProgram().
    ///
    /// Only uploads uniforms whose values have been changed. To ensure that all uniforms
    /// are always uploaded, reset() must be called between releasing and binding the shader
    /// program.
    ///
    /// The shader program must be bound.
    void upload()
    {
        assert(shaderProgram_ !is null,
               "Trying to upload light uniforms without specifying shader program to use");
        assert(shaderProgram_.bound,
               "Trying to upload light uniforms without binding the shader program first");

        // Ambient light.
        ambientLight.uploadIfNeeded(shaderProgram_);

        // Directional lights.
        directionalDirection.uploadIfNeeded(shaderProgram_);
        directionalDiffuse.uploadIfNeeded(shaderProgram_);

        // Point lights.
        pointPositions.uploadIfNeeded(shaderProgram_);
        pointDiffuse.uploadIfNeeded(shaderProgram_);
        pointAttenuations.uploadIfNeeded(shaderProgram_);
    }

    /// Reset uniforms, trigerring a reupload of all uniforms with the next upload() call.
    ///
    /// This should be done between releasing and binding the shader program, as 
    /// all uploaded uniform values are lost when a shader program is released.
    void reset() @safe pure nothrow
    {
        assert(shaderProgram_ !is null,
               "Trying to reset light uniforms without specifying shader program to use");
        ambientLight.reset();
        directionalDirection.reset();
        directionalDiffuse.reset();
        pointPositions.reset();
        pointDiffuse.reset();
        pointAttenuations.reset();
    }
}
