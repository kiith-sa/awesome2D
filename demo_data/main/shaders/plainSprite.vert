attribute vec2 Position;
attribute vec2 TexCoord;

varying vec2 frag_TexCoord;

// Position of the sprite's origin in pixel space.
uniform vec2  spritePosition2D;
// Orthographic projection projecting the sprite to the screen.
uniform mat4  projection;

varying vec2 pixelPosition2D;

void main (void)
{
    frag_TexCoord = TexCoord;
    pixelPosition2D = Position + spritePosition2D;
    gl_Position = projection * vec4(pixelPosition2D, 0.0, 1.0);
}

