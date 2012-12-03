//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Camera with a dimetric projection.
module awesome2d.dimetriccamera;


import gl3n.linalg;


/// Camera with a dimetric projection.
///
/// Supports panning, zooming and changing the vertical view angle.
class DimetricCamera
{
private:
    /// Vertical angle of the projection in radians.
    ///
    /// O is horizontal, PI/4 is isometric, PI/2 is top-down.
    float verticalAngleRadians_;
    /// Plain orthographic projection, without any rotation.
    mat4 orthoMatrix_;
    /// Rotation matrix. Rotates orthoMatrix_ to get the final projection.
    mat4 rotationMatrix_;

public:
    /// Construct a dimetric camera.
    ///
    /// This sets up a default projection, looking at 0,0,0
    /// with size of 640x480 units.
    this() @safe pure nothrow
    {
        // Set up a default projection.
        setProjection(vec2(-320, -240), vec2(640, 480), 2000.0f);
        verticalAngleRadians = PI / 4;
    }

    /// Set parameters of the orthographic projection.
    ///
    /// Params:  offset = X and Y offset  of the projection (panning).
    ///          size   = Size of the projection (zoom).
    ///          depth  = Depth of the projected area - objects within this
    ///                   area will be projected; outside objects will not.
    void setProjection(const vec2 offset, const vec2 size, const float depth) @safe pure nothrow
    {
        orthoMatrix_ = mat4.orthographic(offset.x,          offset.x + size.x, 
                                         offset.y, offset.y + size.y,
                                         depth * -0.5f,      depth * (0.5f));
    }

    /// Set the vertical angle of the projection in radians.
    ///
    /// O is horizontal, PI/4 is isometric, PI/2 is top-down.
    @property void verticalAngleRadians(const float rhs) @safe pure nothrow 
    {
        verticalAngleRadians_ = rhs;
        rotationMatrix_ = mat4.zrotation(0) * mat4.xrotation(rhs) * mat4.yrotation(-PI / 4/*-rhs*/);
    }

    /// Get the vertical angle of the projection in radians.
    ///
    /// O is horizontal, PI/4 is isometric, PI/2 is top-down.
    @property float verticalAngleRadians() @safe const pure nothrow 
    {
        return verticalAngleRadians_;
    }

    /// Get a GL-compatible projection matrix for this camera.
    @property mat4 projection() @safe const pure nothrow 
    {
        return orthoMatrix_ * rotationMatrix_;
    }
}
