//          Copyright Ferdinand Majerech 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// String utility functions.
module util.string;



/// Return a pointer zero-terminated (C) string with the same contents as passed string.
///
/// The string can only be used directly after the call - the next
/// toStringzNoAlloc() call will overwrite it.
const(char*) toStringzNoAlloc(string str) nothrow
{
    static char[] cString;
    if(str.length + 1 > cString.length){cString.length = str.length + 1;}
    cString[0 .. str.length] = str[];
    cString[str.length] = '\0';
    return cast(const char*)cString.ptr;
}
