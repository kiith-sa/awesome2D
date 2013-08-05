attribute vec2 Position;
attribute vec4 Color;

varying vec4 frag_Color;

// Position of the sprite's origin in pixel space.
uniform vec3 spritePosition3D;
// Orthographic projection projecting the sprite to the screen.
uniform mat4 projection;

uniform bool  dimetric;
// Vertical angle of the dimetric view.
uniform float verticalAngle;

varying vec2 pixelPosition2D;


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
    // Unlike with pixel sprite shaders, we project the vertices themselves dimetrically.
    // I.e. the shape changes on the screen, not just its position.

    frag_Color = Color;
    if(dimetric)
    {
        mat4 view   = xRotation(PI / 2.0 - verticalAngle) * zRotation(PI / 4.0);
        // Used for pixel clipping.
        pixelPosition2D = vec2(view * vec4(spritePosition3D + vec3(Position, 0.0), 1.0));
        gl_Position = projection * vec4(pixelPosition2D, 0.0, 1.0);
    }
    else 
    {
        // Used for pixel clipping.
        pixelPosition2D = vec2(spritePosition3D + vec3(Position, 0.0));
        gl_Position = projection * vec4(pixelPosition2D, 0.0, 1.0);
    }
}


