attribute vec2 Position;
attribute vec2 TexCoord;
// Minimum extents of the 3D bounding box of the sprite in object space.
attribute vec3 MinOffsetBounds;
// Maximum extents of the 3D bounding box of the sprite in object space.
attribute vec3 MaxOffsetBounds;

varying vec2 frag_TexCoord;

// Position of the sprite's origin in (3D) world space.
uniform vec3  spritePosition3D;
// Vertical angle of the dimetric view.
uniform float verticalAngle;
// Orthographic projection projecting the sprite to the screen.
uniform mat4  projection;

// Minimum extents of the 3D bounding box of the sprite in world space.
varying vec3  worldSpriteBoundsMin;
// Size of the 3D bounding box of the sprite.
varying vec3  spriteBoundsSize;

const float PI = 3.14159265358979323846264;

// Get a rotation matrix that will rotate a vertex around the X axis by specified angle.
mat4 xRotation(in float angle)
{
    float cosAngle = cos(angle);
    float sinAngle = sin(angle);
    mat4 xRot = mat4(1.0);
    xRot[1][1] = cosAngle;
    xRot[1][2] = -sinAngle;
    xRot[2][1] = sinAngle;
    xRot[2][2] = cosAngle;
    return xRot;
}

// Get a rotation matrix that will rotate a vertex around the Z axis by specified angle.
mat4 zRotation(in float angle)
{
    float cosAngle = cos(angle);
    float sinAngle = sin(angle);
    mat4 zRot = mat4(1.0);
    zRot[0][0] = cosAngle;
    zRot[0][1] = -sinAngle;
    zRot[1][0] = sinAngle;
    zRot[1][1] = cosAngle;
    return zRot;
}

void main (void)
{
    // We start with a 3D position of the sprite in world space and the 
    // vertical angle of the dimetric view, which is 90 for top-down and 
    // about 45 for isometric, and 30 for the low view RTSs like RA2.
    //
    // While the sprite itself is 2D, as its position is 3D we need the view
    // matrix to transform it to camera space.
    //
    // In world space, Y points up and X points right.
    //
    // The view matrix first rotates the space around the Z axis by 45 degrees 
    // (PI / 4). This makes world-space Y point top-right while world-space X 
    // points bottom right. At this point we have a top-down view.
    //
    // Then we rotate the result around the Y axis by 90 - verticalAngle degrees
    // (i.e. PI / 2 - verticalAngle). This changes the top-down view into correctly
    // angled dimetric view.
    //
    // The view matrix consists of these two transformations.
    //
    // After multiplying by the view matrix (transforming to camera space), 
    // we ignore the camera-space Z coordinate - it does not affect the 2D view.
    //
    // The resulting coordinate is the origin of the sprite's 2D position. The
    // vertex position is relative to that.

    mat4 view = xRotation(PI / 2.0 - verticalAngle) * zRotation(PI / 4.0);
    frag_TexCoord = TexCoord;
    vec2 spritePosition2D = vec2(view * vec4(spritePosition3D, 1.0));
    vec2 pos2D = Position + spritePosition2D;

    worldSpriteBoundsMin = spritePosition3D + MinOffsetBounds;
    spriteBoundsSize     = MaxOffsetBounds - MinOffsetBounds;

    gl_Position = projection * vec4(pos2D, 0.0, 1.0);
}
