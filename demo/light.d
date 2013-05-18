//          Copyright Ferdinand Majerech 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Light source types.
module demo.light;


import color;
import spatial.boundingsphere;
import util.linalg;


/// A directional light source.
///
/// A directional light models a very distant light source (e.g. the Sun).
/// The source has no actual position, just a direction.
///
/// Lights can be registered with a LightManager to light a scene.
struct DirectionalLight
{
package:
    // Direction towards the light.
    vec3 direction_ = vec3(0.0f, 0.0f, 1.0f);
    // Diffuse color of the light.
    Color diffuse_  = rgb!"000000";
    // Is this light currently locked (i.e. unmodifiable) ?
    bool locked_ = false;

public:
    /// Construct a directional light.
    ///
    /// Params:  direction = Direction towards the light.
    ///          diffuse   = Diffuse color of the light.
    this(const vec3 direction, const Color diffuse)
    {
        direction_ = direction;
        diffuse_   = diffuse;
    }

    /// Get direction towards the light.
    @property vec3 direction() @safe const pure nothrow {return direction_;}

    /// Get diffuse color of the light.
    @property Color diffuse() @safe const pure nothrow {return diffuse_;}

    /// Set direction towards the light.
    ///
    /// Can only be called if the light is not registered to a locked LightManager.
    @property void direction(const vec3 rhs) @safe pure nothrow 
    {
        assert(!locked_, "Can't modify a directional light - lights are locked'");
        direction_ = rhs;
    }

    /// Set diffuse color of the light.
    ///
    /// Can only be called if the light is not registered to a locked LightManager.
    @property void diffuse(const Color rhs) @safe pure nothrow 
    {
        assert(!locked_, "Can't modify a directional light - lights are locked'");
        diffuse_ = rhs;
    }
}

/// A point light source.
///
/// A point light has a position in 3D space and lits surrounding objects in a
/// sphere. The lighting is stronger on closer objects than on those that are more distant.
///
/// Lights can be registered with a LightManager to light a scene.
struct PointLight
{
private:
    // 3D position of the light source.
    vec3 position_     = vec3(0.0f, 0.0f, 1.0f);
    // Diffuse color of the light.
    Color diffuse_     = rgb!"000000";
    // Attenuation factor of the light.
    float attenuation_ = 1.0f;
    // Bounding sphere of the light, used to determine which point lights affect a sprite.
    BoundingSphere boundingSphere_;

package:
    // Is this light currently locked (i.e. unmodifiable) ?
    bool locked_ = false;

public:
    /// Construct a point light.
    ///
    /// Params:  position    = 3D position of the light.
    ///          diffuse     = Diffuse color of the light.
    ///          attenuation = Attenuation factor of the light, determining how fast does the
    ///                        light weaken with distance.
    this(const vec3 position, const Color diffuse, const float attenuation)
    {
        // Go through setters.
        this.position    = position;
        this.diffuse     = diffuse;
        this.attenuation = attenuation;
        boundingSphere_.center = vec3(0, 0, 0);
    }

    /// Get 3D position of the light source.
    @property vec3 position() @safe const pure nothrow {return position_;}

    /// Get diffuse color of the light.
    @property Color diffuse() @safe const pure nothrow {return diffuse_;}

    /// Get attenuation factor of the light.
    @property float attenuation() @safe const pure nothrow {return attenuation_;}

    /// Get bounding sphere of the light, used to determine which point lights affect a sprite.
    @property ref const(BoundingSphere) boundingSphere() @safe const pure nothrow
    {
        return boundingSphere_;
    }

    /// Set 3D position of the light source.
    ///
    /// Can only be called if the light is not registered to a locked LightManager.
    @property void position(const vec3 rhs) @safe pure nothrow 
    {
        assert(!locked_, "Can't modify a point light - lights are locked'");
        position_ = rhs;
    }

    /// Set diffuse color of the light.
    ///
    /// Can only be called if the light is not registered to a locked LightManager.
    @property void diffuse(const Color rhs) @safe pure nothrow 
    {
        assert(!locked_, "Can't modify a point light - lights are locked'");
        diffuse_ = rhs;
    }

    /// Set attenuation factor of the light.
    ///
    /// Increasing this value causes the light to weaken faster with distance.
    /// Values between 0 and 1 result in a larger area light. 0 completely removes
    /// the attenuation effect, making the light affect all objects, regardless of distance.
    ///
    /// Negative values will result in undefined behavior.
    ///
    /// Can only be called if the light is not registered to a locked LightManager.
    @property void attenuation(const float rhs) @safe pure nothrow 
    {
        assert(!locked_, "Can't modify a point light - lights are locked'");
        attenuation_ = rhs;
        // TODO decrease once HDR and quadratic attentuation is implemented
        boundingSphere_.radius = 256 / attenuation_;
    }
}
