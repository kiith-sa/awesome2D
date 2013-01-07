uniform sampler2D texDiffuse;
uniform sampler2D texNormal;
uniform sampler2D texOffset;
uniform vec3  spritePosition3D;
uniform vec3  minBounds;
uniform vec3  maxBounds;
varying vec2 frag_TexCoord;

// Ambient light
uniform vec3 ambientLight;

// Directional lights
const int directionalLightCount = 4;
uniform vec3 directionalDirections[directionalLightCount];
// Diffuse colors for unused light sources must be black.
uniform vec3 directionalDiffuse[directionalLightCount];

// Point lights
const int pointLightCount = 8;
uniform vec3  pointPositions[pointLightCount];
// Diffuse colors for unused light sources must be black.
uniform vec3  pointDiffuse[pointLightCount];
uniform float pointAttenuations[pointLightCount];

/// Compute lighting contribution from one directional light source.
///
/// Params: light        = Index of the light source in the directionalXXX arrays.
///         pixelDiffuse = Diffuse color of the processed pixel of the sprite.
///         pixelNormal  = Normalized normal vector of the processed pixel of the sprite.
///
/// Returns: Color added to the result pixel color by the light source.
vec3 directionalLighting(in int light, in vec3 pixelDiffuse, in vec3 pixelNormal)
{
    vec3 lightDirection = normalize(directionalDirections[light]);
    vec3 reflectedColor = directionalDiffuse[light] * pixelDiffuse;
    return reflectedColor * max(0.0, dot(pixelNormal, lightDirection));
}

/// Compute the total contribution of all directional light sources.
///
/// Params: pixelDiffuse = Diffuse color of the processed pixel of the sprite.
///         pixelNormal  = Normalized normal vector of the processed pixel of the sprite.
///
/// Returns: The sum of colors added th the result pixel color by all directional lights.
vec3 directionalLightingTotal(in vec3 pixelDiffuse, in vec3 pixelNormal)
{
    vec3 result = vec3(0.0, 0.0, 0.0);
    // Loop unrolled to avoid branches. 
    // Unused light sources have black color so they won't affect the result.
    result += directionalLighting(0, pixelDiffuse, pixelNormal);
    result += directionalLighting(1, pixelDiffuse, pixelNormal);
    result += directionalLighting(2, pixelDiffuse, pixelNormal);
    result += directionalLighting(3, pixelDiffuse, pixelNormal);
    return result;
}

/// Compute lighting contribution from one point light source.
///
/// Params: light         = Index of the light source in pointLights.
///         pixelDiffuse  = Diffuse color of the processed pixel of the sprite.
///         pixelNormal   = Normalized normal vector of the processed pixel of the sprite.
///         pixelPosition = Position of the pixel in 3D space.
///
/// Returns: Color added to the result pixel color by the light source.
vec3 pointLighting(in int light, in vec3 pixelDiffuse, in vec3 pixelNormal,
                   in vec3 pixelPosition)
{
    vec3 posToLight = pointPositions[light] - pixelPosition;
    float distance  = length(posToLight);
    // Normalize lightDirection; no need to compute sqrt again.
    vec3 lightDirection = posToLight / distance;

    // 64 distance units (pixels in our case) are one lighting distance unit.
    // Avoids needing to use extremely low attenuation values.
    // Linear attenuation for now. TODO quadratic once we get HDR.
    float attenuationFactor = 1.0 / (1.0 + pointAttenuations[light] * (distance / 64.0));
    vec3 reflectedColor = pointDiffuse[light] * pixelDiffuse;
    return attenuationFactor * reflectedColor * max(0.00, dot(pixelNormal, lightDirection));
}

vec3 pointLightingTotal(in vec3 pixelDiffuse, in vec3 pixelNormal, in vec3 pixelPosition)
{
    vec3 result = vec3(0.0, 0.0, 0.0);
    // Loop unrolled to avoid branches. 
    // Unused light sources have black color so they won't affect the result.
    result += pointLighting(0, pixelDiffuse, pixelNormal, pixelPosition);
    result += pointLighting(1, pixelDiffuse, pixelNormal, pixelPosition);
    result += pointLighting(2, pixelDiffuse, pixelNormal, pixelPosition);
    result += pointLighting(3, pixelDiffuse, pixelNormal, pixelPosition);
    result += pointLighting(4, pixelDiffuse, pixelNormal, pixelPosition);
    result += pointLighting(5, pixelDiffuse, pixelNormal, pixelPosition);
    result += pointLighting(6, pixelDiffuse, pixelNormal, pixelPosition);
    result += pointLighting(7, pixelDiffuse, pixelNormal, pixelPosition);
    return result;
}

void main (void)
{
    // Color of the sprite.
    vec3 diffuse  = vec3(texture2D(texDiffuse, frag_TexCoord));
    // We preserve transparency of the sprite.
    float alpha   = texture2D(texDiffuse, frag_TexCoord).a;
    // Map the normal coordinates from [0.0, 1.0] to [-1.0, 1.0]
    vec3 normal   = vec3(texture2D(texNormal, frag_TexCoord));
    normal        = normalize(normal * 2.0 - vec3(1.0, 1.0, 1.0));
    // Map offset coordinates from [0.0, 1.0] to [minBounds, maxBounds]
    // and add that to sprite position to get position of the pixel.
    vec3 offset   = vec3(texture2D(texOffset, frag_TexCoord));
    vec3 position = spritePosition3D + minBounds + (maxBounds - minBounds) * offset;

    // Add up lighting from all types of light sources.
    vec3 totalLighting = ambientLight * diffuse
                       + directionalLightingTotal(diffuse, normal)
                       + pointLightingTotal(diffuse, normal, position);

    gl_FragColor = vec4(totalLighting, alpha);
}
