
//          Copyright Ferdinand Majerech 2010 - 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


///2D image struct.
module image;


import core.stdc.string;

import color;
import memory.memory;
import util.linalg;


//could be optimized by adding a pitch data member (bytes per row)    
///Image object capable of storing images in various color formats.
struct Image
{
//commented out due to a compiler bug
//invariant(){assert(data_ !is null, "Image with NULL data");}

private:
    ///Image data. Manually allocated.
    ubyte[] data_ = null;
    ///Size of the image in pixels.
    vec2u size_;
    ///Color format of the image.
    ColorFormat format_;

public:
    /**
     * Construct an image.
     *
     * The image will be black, and if it has an alpha channel, transparent.
     *
     * Params:  width  = Width in pixels.
     *          height = Height in pixels.
     *          format = Color format of the image.
     */
    this(const uint width, const uint height, 
         const ColorFormat format = ColorFormat.RGBA_8) @trusted
    {
        data_ = allocArray!ubyte(width * height * bytesPerPixel(format));
        size_ = vec2u(width, height);
        format_ = format;
    }

    /// Postblit constructor for copying.
    this(this)
    {
        const oldData = data_;
        const bytes = width * height * bytesPerPixel(format_);
        data_ = allocArray!ubyte(bytes);
        memcpy(data_.ptr, oldData.ptr, bytes);
    }

    /// Downsample a high-resolution image to a lower resolution.
    ///
    /// This is only useful for things like anti-aliasing when a higher-resolution 
    /// image can be trivially downsampled. It only works if the image width
    /// and height are divisible by the downsampling level.
    ///
    /// Params:  downSamplingLevel = Size of a square of pixels that will be replaced by
    ///                              a single pixel in the downsampled image.
    ///                              E.g. if this is 2, every 2x2 pixels will be averaged
    ///                              into 1 pixel in the result.
    ///                              Image width and height must be divisible by this value.
    ///
    /// Returns: Downsampled image.
    Image downSampled(const uint downSamplingLevel) @trusted
    {
        assert(downSamplingLevel > 0 &&
               width % downSamplingLevel == 0 &&
               height % downSamplingLevel == 0,
               "Image.downSample(): image width and height "
               "must be divisible by downSamplingLevel");

        Image result = Image(width / downSamplingLevel, height / downSamplingLevel, format);

        foreach(y; 0 .. result.height) foreach(x; 0 .. result.width)
        {
            vec4 total = vec4(0, 0, 0, 0);
            const ySource = y * downSamplingLevel;
            const xSource = x * downSamplingLevel;
            foreach(ySample; ySource .. ySource + downSamplingLevel)
            {
                foreach(xSample; xSource .. xSource + downSamplingLevel)
                {
                    const pixel = getPixel(xSample, ySample).toVec4();
                    total = vec4(total.rgb + pixel.rgb * pixel.a, total.a + pixel.a);
                }
            }

            // Transparent area of the pixels doesn't contribute to the total color.
            //
            // We average the opague area for the color,
            // while alpha is the average of all pixels.
            const totalPixels  = downSamplingLevel * downSamplingLevel;
            const opaguePixels = total.a;
            const average = vec4(total.rgb * (1.0f / opaguePixels),
                                 total.a   * (1.0f / totalPixels));
            result.setPixel(x, y, Color.fromVec4(average));
        }

        return result;
    }

    ///Destroy the image and free its memory.
    @trusted nothrow ~this(){if(data !is null){free(data_);}}

    ///Get color format of the image.
    @property ColorFormat format() @safe const pure nothrow {return format_;}

    ///Get size of the image in pixels.
    @property vec2u size() @safe const pure nothrow {return size_;}

    ///Get image width in pixels.
    @property uint width() @safe const pure nothrow {return size_.x;}

    ///Get image height in pixels.
    @property uint height() @safe const pure nothrow {return size_.y;}

    ///Get direct read-only access to image data.
    @property const(ubyte[]) data() @safe const pure nothrow {return data_;}

    ///Get direct read-write access to image data.
    @property ubyte[] dataUnsafe() pure nothrow {return data_;}

    /**
     * Set pixel color.
     *
     * Only valid on GRAY_8, RGB_8 and RGBA_8 images.
     * Alpha will be ignored the format doesn't support it.
     * For grayscale, luminance of the color will be used.
     *
     * Params:  x     = X coordinate of the pixel.
     *          y     = Y coordinate of the pixel.
     *          color = Color to set.
     */
    void setPixel(const uint x, const uint y, const Color color) @safe nothrow
    in
    {
        assert(x < size_.x && y < size_.y, "Pixel out of range");
        assert(format == ColorFormat.RGBA_8 || 
               format == ColorFormat.RGB_8 ||
               format == ColorFormat.GRAY_8, "Incorrect image format");
    }
    body
    {
        const uint offset = y * pitch + x * bytesPerPixel(format_);
        switch(format)
        {
            case ColorFormat.RGBA_8:
                data_[offset]     = color.r;
                data_[offset + 1] = color.g;
                data_[offset + 2] = color.b;
                data_[offset + 3] = color.a;
                break;
            case ColorFormat.RGB_8:
                data_[offset]     = color.r;
                data_[offset + 1] = color.g;
                data_[offset + 2] = color.b;
                break;
            case ColorFormat.GRAY_8:
                data_[offset]     = color.luminance;
                break;
            default:
                assert(false, "Unsupported color format form Image.setPixel()");
        }
    }

    /**
     * Set grayscale pixel color.
     *
     * Only valid on GRAY_8 images.
     *
     * Params:  x     = X coordinate of the pixel.
     *          y     = Y coordinate of the pixel.
     *          color = Color to set.
     */
    void setPixelGray8(const uint x, const uint y, const ubyte color) @safe pure nothrow
    in
    {
        assert(x < size_.x && y < size_.y, "Pixel out of range");
        assert(format == ColorFormat.GRAY_8, "Incorrect image format");
    }
    body{data_[y * pitch + x] = color;}

    /**
     * Get color of a pixel.
     *
     * Only supported on GRAY_8, RGB_8 and RGBA_8 images at the moment (can be improved).
     *
     * Params:  x = X coordinate of the pixel.
     *          y = Y coordinate of the pixel.
     *
     * Returns: Color of the pixel.
     */
    Color getPixel(const uint x, const uint y) @safe const pure nothrow
    in
    {
        assert(x < size_.x && y < size_.y, "Pixel out of range");
        assert(format == ColorFormat.RGBA_8 || format == ColorFormat.RGB_8,
               "Getting pixel color only supported with RGBA_8");
    }
    body
    {
        const uint offset = y * pitch + x * bytesPerPixel(format_);
        switch(format)
        {
            case ColorFormat.RGBA_8:
                return Color(data_[offset],     data_[offset + 1],
                             data_[offset + 2], data_[offset + 3]);
            case ColorFormat.RGB_8:
                return Color(data_[offset], data_[offset + 1], data_[offset + 2], 255);
            case ColorFormat.GRAY_8:
                const gray = data_[offset];
                return Color(gray, gray, gray, 255);
            default:
                assert(false, "Unsupported color format for Image.getPixel()");
        }
    }

    //This is extremely ineffective/ugly, but not really a priority
    /**
     * Generate a black/transparent-white/opague checker pattern.
     *
     * Params:  size = Size of one checker square.
     */
    void generateCheckers(const uint size) @safe nothrow
    {
        bool white;
        foreach(y; 0 .. size_.y) foreach(x; 0 .. size_.x)
        {
            white = cast(bool)(x / size % 2);
            if(cast(bool)(y / size % 2)){white = !white;}
            if(white) final switch(format_)
            {
                case ColorFormat.RGB_565, 
                     ColorFormat.RGB_5,
                     ColorFormat.RGBA_5551,
                     ColorFormat.RGBA_4:
                    data_[y * pitch + x * 2] = 255;
                    data_[y * pitch + x * 2 + 1] = 255;
                    break;
                case ColorFormat.RGB_8, ColorFormat.RGBA_8, ColorFormat.GRAY_8:
                    setPixel(x, y, Color.white);
                    break;
            }
            else switch(format_)
            {
                case ColorFormat.RGBA_8:
                    setPixel(x, y, Color.black);
                    break;
                default:
                    // If alpha is disabled, black is the default.
            }
        }
    }

    //This is extremely ineffective/ugly, but not really a priority
    /**
     * Generate a black/transparent-white/opague stripe pattern
     *
     * Params:  distance = Distance between 1 pixel wide stripes.
     */
    void generateStripes(const uint distance) @safe nothrow
    {
        foreach(y; 0 .. size_.y) foreach(x; 0 .. size_.x)
        {
            if(cast(bool)(x % distance == y % distance)) final switch(format_)
            {
                case ColorFormat.RGB_565, 
                     ColorFormat.RGB_5,
                     ColorFormat.RGBA_5551,
                     ColorFormat.RGBA_4:
                    data_[y * pitch + x * 2] = 255;
                    data_[y * pitch + x * 2 + 1] = 255;
                    break;
                case ColorFormat.RGB_8, ColorFormat.RGBA_8, ColorFormat.GRAY_8:
                    setPixel(x, y, Color.white);
                    break;
            }
        }
    }

    ///Gamma correct the image with specified factor.
    void gammaCorrect(const real factor) @safe nothrow
    in{assert(factor >= 0.0, "Gamma correction factor must not be negative");}
    body
    {
        Color pixel;
        foreach(y; 0 .. size_.y) foreach(x; 0 .. size_.x)
        {
            switch(format_)
            {
                case ColorFormat.RGBA_8:
                    pixel = getPixel(x, y);
                    pixel.gammaCorrect(factor);
                    setPixel(x, y, pixel);
                    break;
                case ColorFormat.GRAY_8:
                    setPixelGray8(x, y, 
                    Color.gammaCorrect(data_[y * pitch + x], factor));
                    break;
                default:
                    assert(false, "Unsupported color format for gamma correction");
            }
        }
    }

    ///Flip the image vertically.
    void flipVertical() @trusted
    {
        const uint pitch = pitch();
        ubyte[] tempRow = allocArray!ubyte(pitch);
        foreach(row; 0 .. size_.y / 2)
        {
            //swap row and size_.y - row
            ubyte* rowA = data_.ptr + pitch * row;
            ubyte* rowB = data_.ptr + pitch * (size_.y - row - 1);
            memcpy(tempRow.ptr, rowA, pitch);
            memcpy(rowA, rowB, pitch);
            memcpy(rowB, tempRow.ptr, pitch);
        }
        free(tempRow);
    }

private:
    ///Get pitch (bytes per row) of the image.
    @property uint pitch() @safe const pure nothrow {return bytesPerPixel(format_) * size_.x;}
}
