/*

Boost Software License - Version 1.0 - August 17th, 2003

Permission is hereby granted, free of charge, to any person or organization
obtaining a copy of the software and accompanying documentation covered by
this license (the "Software") to use, reproduce, display, distribute,
execute, and transmit the Software, and to prepare derivative works of the
Software, and to permit third-parties to whom the Software is furnished to
do so, all subject to the following:

The copyright notices in the Software and this entire statement, including
the above license grant, this restriction and the following disclaimer,
must be included in all copies of the Software, in whole or in part, and
all derivative works of the Software, unless such copies or derivative
works are solely in the form of machine-executable object code generated by
a source language processor.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.

*/
module derelict.ogg.vorbisfiletypes;

private
{
    import derelict.util.compat;
    import derelict.ogg.oggtypes;
    import derelict.ogg.vorbistypes;
    import derelict.ogg.vorbisenctypes;
}

extern (C)
{
    struct ov_callbacks
    {
        size_t function(void* ptr, size_t size, size_t nmemb, void* datasource ) read_func;
        int function(void* datasource, ogg_int64_t offset, int whence ) seek_func;
        int function(void* datasource ) close_func;
        c_long function(void* datasource ) tell_func;
    }
}

enum
{
    NOTOPEN   =0,
    PARTOPEN  =1,
    OPENED    =2,
    STREAMSET =3,
    INITSET   =4,
}

struct OggVorbis_File
{   void            *datasource;
    int              seekable;
    ogg_int64_t      offset;
    ogg_int64_t      end;
    ogg_sync_state   oy;
    int              links;
    ogg_int64_t     *offsets;
    ogg_int64_t     *dataoffsets;
    c_long             *serialnos;
    ogg_int64_t     *pcmlengths;
    vorbis_info     *vi;
    vorbis_comment  *vc;
    ogg_int64_t      pcm_offset;
    int              ready_state;
    c_long              current_serialno;
    int              current_link;
    double           bittrack;
    double           samptrack;
    ogg_stream_state os;
    vorbis_dsp_state vd;
    vorbis_block     vb;

    ov_callbacks callbacks;
}