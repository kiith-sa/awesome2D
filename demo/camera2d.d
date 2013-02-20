//          Copyright Ferdinand Majerech 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/// Camera used in a 2D scene.
module demo.camera2d;


import gl3n.linalg;


/// Camera used in a 2D scene.
class Camera2D
{
private:
    // Position of the center of the camera in pixels (the point we're looking at).
    vec2i center_ = vec2u(0, 0);

    // Size of the viewport.
    vec2u size_ = vec2u(640, 480);

    // Current zoom level.
    float zoom_ = 1.0f;

    // Projection matrix to transform vertices from camera space to screen space.
    mat4 projection_;

public:
    /// Construct a Camera2D with default parameters (center at (0,0), no zoom, 640x480).
    this()
    {
        updateProjection();
    }

    /// Set position of the center of the camera in pixels (the point we're looking at).
    @property void center(const vec2i rhs) @safe pure nothrow 
    {
        center_ = rhs;
        updateProjection();
    }

    /// Get the position of the center of the camera in pixels.
    @property vec2i center() @safe const pure nothrow {return center_;}

    /// Set camera zoom. 
    ///
    /// Values greater than 1 result in a "closer" (pixelated) view.
    /// Values between 0 and 1 result in zooming out.
    /// Must be greater than zero.
    @property void zoom(const float rhs) pure nothrow 
    {
        assert(rhs > 0.0, "Zoom must be greater than zero");
        zoom_ = rhs;
        updateProjection();
    }

    /// Get camera zoom.
    @property float zoom() @safe const pure nothrow {return zoom_;}

    /// Set size of the viewport in pixels. Both dimensions must be greater than zero.
    @property void size(const vec2u rhs) @safe pure nothrow 
    {
        assert(rhs.x > 0 && rhs.y > 0, "Camera can't have zero size'");
        size_ = rhs;
        updateProjection();
    }

    /// Get size of the viewport in pixels.
    @property vec2u size() const pure nothrow {return size_;}

    /// Return a GLSL-compatible projection matrix.
    @property ref const(mat4) projection() @safe const pure nothrow {return projection_;}

private:
    // Update the projection matrix (called when a camera parameter changes.
    void updateProjection() @safe pure nothrow
    {
        auto zoomedHalfSize = (vec2(size_.x, size_.y) * 0.5f) * (1.0f / zoom_);
        projection_ = mat4.orthographic
            (center_.x - zoomedHalfSize.x, center_.x + zoomedHalfSize.x,
             center_.y - zoomedHalfSize.y, center_.y + zoomedHalfSize.y,
             -100.0f, 100.0f);
    }
}
