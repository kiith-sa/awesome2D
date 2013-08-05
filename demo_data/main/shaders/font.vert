attribute vec2 Position;
attribute vec2 TexCoord;

varying vec2 frag_TexCoord;

// Position of the sprite's origin in pixel space.
uniform vec3  spritePosition3D;
// Orthographic projection projecting the sprite to the screen.
uniform mat4  projection;

varying vec2 pixelPosition2D;

uniform bool  dimetric;
// Vertical angle of the dimetric view.
uniform float verticalAngle;

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
    // Position the character dimetrically.
    // This will allow us to position e.g. characters correctly relative to map coordinates.
    vec2 spritePosition2D = vec2(spritePosition3D);
    if(dimetric)
    {
        mat4 view = xRotation(PI / 2.0 - verticalAngle) * zRotation(PI / 4.0);
        spritePosition2D = vec2(view * vec4(spritePosition3D, 1.0));
    }

    frag_TexCoord = TexCoord;
    pixelPosition2D = Position + spritePosition2D;
    gl_Position = projection * vec4(pixelPosition2D, 0.0, 1.0);
}


