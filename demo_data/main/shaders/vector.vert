attribute vec2 Position;
attribute vec4 Color;

varying vec4 frag_Color;

// Position of the sprite's origin in pixel space.
uniform vec2 spritePosition2D;
// Orthographic projection projecting the sprite to the screen.
uniform mat4 projection;

varying vec2 pixelPosition2D;

void main (void)
{
    frag_Color      = Color;
    pixelPosition2D = Position + spritePosition2D;
    gl_Position     = projection * vec4(pixelPosition2D, 0.0, 1.0);
}


