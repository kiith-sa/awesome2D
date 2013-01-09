//          Copyright Ferdinand Majerech 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Light source types.
module demo.light;


import gl3n.linalg;

import color;


/// A directional light source.
///
/// A directional light models a very distant light source (e.g. the Sun).
/// The source has no actual position, just a direction.
struct DirectionalLight
{
    /// Direction towards the light.
    vec3 direction = vec3(0.0f, 0.0f, 1.0f);
    /// Diffuse color of the light.
    Color diffuse  = rgb!"000000";
}

/// A point light source.
///
/// A point light has a position in 3D space and lits surrounding objects in a
/// sphere. The lighting is stronger on closer objects than on those that are more distant.
struct PointLight
{
    /// 3D position of the light source.
    vec3 position     = vec3(0.0f, 0.0f, 1.0f);
    /// Diffuse color of the light.
    Color diffuse     = rgb!"000000";
    /// Attenuation factor of the light.
    ///
    /// Increasing this value causes the light to weaken faster with distance.
    /// Values between 0 and 1 result in a larger area light. 0 completely removes
    /// the attenuation effect, making the light affect all objects, regardless of distance.
    ///
    /// Negative values will result in undefined behavior.
    float attenuation = 1.0f;
}
