uniform sampler2D texDiffuse;
uniform sampler2D texNormal;
uniform sampler2D texOffset;
uniform vec3  spritePosition3D;
uniform vec3  minClipBounds;
uniform vec3  maxClipBounds;
varying vec2  frag_TexCoord;

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

// Minimum extents of the 3D bounding box of the sprite in world space.
varying vec3  worldSpriteBoundsMin;
// Size of the 3D bounding box of the sprite.
varying vec3  spriteBoundsSize;

/// Compute lighting contribution from one directional light source.
///
/// Params: light        = Index of the light source in the directionalXXX arrays.
///         pixelDiffuse = Diffuse color of the processed pixel of the sprite.
///         pixelNormal  = Normalized normal vector of the processed pixel of the sprite.
///
/// Returns: Color added to the result pixel color by the light source.
vec3 directionalLighting(in int light, in vec3 pixelDiffuse, in vec3 pixelNormal)
{
    vec3 reflectedColor = directionalDiffuse[light] * pixelDiffuse;
    return reflectedColor * 
        max(0.0, dot(pixelNormal, directionalDirections[light]));
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
    if(directionalDiffuse[2] == vec3(0.0, 0.0, 0.0)){return result;}
    result += directionalLighting(2, pixelDiffuse, pixelNormal);
    result += directionalLighting(3, pixelDiffuse, pixelNormal);
    return result;
}

/*
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
    float attenuationFactor = 1.0 / (pointAttenuations[light] * (distance / 64.0) + 1.0);
    vec3 reflectedColor = pointDiffuse[light] * pixelDiffuse;
    return attenuationFactor * reflectedColor * max(0.0, dot(pixelNormal, lightDirection));
}
*/

vec3 pointLightingTotal(in vec3 pixelDiffuse, in vec3 pixelNormal, in vec3 pixelPosition)
{
    vec3 result = vec3(0.0, 0.0, 0.0);

    const float worldToLighting = 1.0 / 64.0; 

    vec3 posToLight0         = pointPositions[0] - pixelPosition;
    vec3 posToLight1         = pointPositions[1] - pixelPosition;

    float distance0          = length(posToLight0);
    float distance1          = length(posToLight1);

    vec3 lightDirection0     = posToLight0 / distance0;
    vec3 lightDirection1     = posToLight1 / distance1;

    float attenuationFactor0 = 1.0 / (pointAttenuations[0] * distance0 * worldToLighting + 1.0);
    float attenuationFactor1 = 1.0 / (pointAttenuations[1] * distance1 * worldToLighting + 1.0);

    vec3 reflectedColor0     = pointDiffuse[0] * pixelDiffuse;
    vec3 reflectedColor1     = pointDiffuse[1] * pixelDiffuse;

    result += attenuationFactor0 * reflectedColor0 * max(0.0, dot(pixelNormal, lightDirection0));
    result += attenuationFactor1 * reflectedColor1 * max(0.0, dot(pixelNormal, lightDirection1));

    if(pointDiffuse[2] == vec3(0.0, 0.0, 0.0)){return result;}

    vec3 posToLight2         = pointPositions[2] - pixelPosition;
    vec3 posToLight3         = pointPositions[3] - pixelPosition;
    float distance2          = length(posToLight2);
    float distance3          = length(posToLight3);
    vec3 lightDirection2     = posToLight2 / distance2;
    vec3 lightDirection3     = posToLight3 / distance3;
    float attenuationFactor2 = 1.0 / (pointAttenuations[2] * distance2 * worldToLighting + 1.0);
    float attenuationFactor3 = 1.0 / (pointAttenuations[3] * distance3 * worldToLighting + 1.0);
    vec3 reflectedColor2     = pointDiffuse[2] * pixelDiffuse;
    vec3 reflectedColor3     = pointDiffuse[3] * pixelDiffuse;
    result += attenuationFactor2 * reflectedColor2 * max(0.0, dot(pixelNormal, lightDirection2));
    result += attenuationFactor3 * reflectedColor3 * max(0.0, dot(pixelNormal, lightDirection3));

    if(pointDiffuse[4] == vec3(0.0, 0.0, 0.0)){return result;}

    vec3 posToLight4         = pointPositions[4] - pixelPosition;
    vec3 posToLight5         = pointPositions[5] - pixelPosition;
    float distance4          = length(posToLight4);
    float distance5          = length(posToLight5);
    vec3 lightDirection4     = posToLight4 / distance4;
    vec3 lightDirection5     = posToLight5 / distance5;
    float attenuationFactor4 = 1.0 / (pointAttenuations[4] * distance4 * worldToLighting + 1.0);
    float attenuationFactor5 = 1.0 / (pointAttenuations[5] * distance5 * worldToLighting + 1.0);
    vec3 reflectedColor4     = pointDiffuse[4] * pixelDiffuse;
    vec3 reflectedColor5     = pointDiffuse[5] * pixelDiffuse;
    result += attenuationFactor4 * reflectedColor4 * max(0.0, dot(pixelNormal, lightDirection4));
    result += attenuationFactor5 * reflectedColor5 * max(0.0, dot(pixelNormal, lightDirection5));

    if(pointDiffuse[6] == vec3(0.0, 0.0, 0.0)){return result;}

    vec3 posToLight6         = pointPositions[6] - pixelPosition;
    vec3 posToLight7         = pointPositions[7] - pixelPosition;
    float distance6          = length(posToLight6);
    float distance7          = length(posToLight7);
    vec3 lightDirection6     = posToLight6 / distance6;
    vec3 lightDirection7     = posToLight7 / distance7;
    float attenuationFactor6 = 1.0 / (pointAttenuations[6] * distance6 * worldToLighting + 1.0);
    float attenuationFactor7 = 1.0 / (pointAttenuations[7] * distance7 * worldToLighting + 1.0);
    vec3 reflectedColor6     = pointDiffuse[6] * pixelDiffuse;
    vec3 reflectedColor7     = pointDiffuse[7] * pixelDiffuse;
    result += attenuationFactor6 * reflectedColor6 * max(0.0, dot(pixelNormal, lightDirection6));
    result += attenuationFactor7 * reflectedColor7 * max(0.0, dot(pixelNormal, lightDirection7));

    return result;
}

void main (void)
{
    // Map offset coordinates from [0.0, 1.0] to [minOffsetBounds, maxOffsetBounds]
    // and add that to sprite position to get position of the pixel.
    vec3 offset   = vec3(texture2D(texOffset, frag_TexCoord));
    vec3 position = spriteBoundsSize * offset + worldSpriteBoundsMin;
    if(position.x < minClipBounds.x || 
       position.y < minClipBounds.y ||
       position.z < minClipBounds.z ||
       position.x > maxClipBounds.x ||
       position.y > maxClipBounds.y ||
       position.z > maxClipBounds.z)
    {
        // We're not drawing in this part of space.
        discard;
    }

    // Color of the sprite.
    vec3 diffuse  = vec3(texture2D(texDiffuse, frag_TexCoord));
    // We preserve transparency of the sprite.
    float alpha   = texture2D(texDiffuse, frag_TexCoord).a;
    // Map the normal coordinates from [0.0, 1.0] to [-1.0, 1.0]
    vec3 normal   = vec3(texture2D(texNormal, frag_TexCoord));
    normal        = normalize(normal * 2.0 - vec3(1.0, 1.0, 1.0));

    // Add up lighting from all types of light sources.
    vec3 totalLighting = ambientLight * diffuse
                       + directionalLightingTotal(diffuse, normal)
                       + pointLightingTotal(diffuse, normal, position);

    gl_FragColor = vec4(totalLighting, alpha);
}
