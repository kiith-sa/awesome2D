//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Camera with a dimetric projection.
module prerenderer.dimetriccamera;


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
    /// Projection matrix. Plain orthographic projection.
    mat4 projection_;
    /// View matrix.
    mat4 view_;

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
        projection_ = mat4.orthographic(offset.x,      offset.x + size.x, 
                                         offset.y,      offset.y + size.y,
                                         depth * -0.5f, depth * (0.5f));
    }

    /// Set the vertical angle of the projection in radians.
    ///
    /// O is horizontal, PI/4 is isometric, PI/2 is top-down.
    @property void verticalAngleRadians(const float rhs) @safe pure nothrow 
    {
        verticalAngleRadians_ = rhs;
        view_ = mat4.zrotation(0) * mat4.xrotation(rhs) * mat4.yrotation(-PI / 4/*-rhs*/);
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
        return projection_;
    }

    /// Get a GL-compatible view matrix for this camera.
    @property mat4 view() @safe const pure nothrow 
    {
        // Rotate so Z is "up-down", not "in-out of the screen".
        return view_ * mat4.xrotation(-PI / 2);
    }
}
