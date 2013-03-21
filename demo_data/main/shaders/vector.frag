uniform vec2 min2DClipBounds;
uniform vec2 max2DClipBounds;
varying vec4 frag_Color;

varying vec2 pixelPosition2D;

void main (void)
{
    if(pixelPosition2D.x < min2DClipBounds.x || 
       pixelPosition2D.y < min2DClipBounds.y ||
       pixelPosition2D.x > max2DClipBounds.x ||
       pixelPosition2D.y > max2DClipBounds.y)
    {
        // Clipped out.
        discard;
    }

    // Color of the pixel.
    gl_FragColor = frag_Color;
}

