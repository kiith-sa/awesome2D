
//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Exceptions thrown by video code.
module video.exceptions;


/// Exception thrown at renderer errors.
class RendererException: Exception 
{
    public this(string msg, string file = __FILE__, int line = __LINE__)
    {
        super(msg, file, line);
    }
}

/// Exception thrown at renderer initialization errors.
class RendererInitException: RendererException 
{
    public this(string msg, string file = __FILE__, int line = __LINE__)
    {
        super(msg, file, line);
    }
}

/// Thrown at all GLSL related errors.
class GLSLException: RendererException
{
    public this(string msg, string file = __FILE__, int line = __LINE__)
    {
        super(msg, file, line);
    }
}

/// Exception thrown at GLSL shader initialization errors.
class GLSLCompileException: RendererException
{
    public this(string msg, string file = __FILE__, int line = __LINE__)
    {
        super(msg, file, line);
    }
}

/// Thrown at GLSL linking related errors.
class GLSLLinkException: GLSLException
{
    public this(string msg, string file = __FILE__, int line = __LINE__)
    {
        super(msg, file, line);
    }
}

/// Thrown at GLSL uniform related errors.
class GLSLUniformException: GLSLException
{
    public this(string msg, string file = __FILE__, int line = __LINE__)
    {
        super(msg, file, line);
    }
}

/// Thrown at GLSL attribute related errors.
class GLSLAttributeException: GLSLException
{
    public this(string msg, string file = __FILE__, int line = __LINE__)
    {
        super(msg, file, line);
    }
}

package:
/// Exception thrown at texture initialization errors.
class TextureInitException : RendererException
{
    public this(string msg, string file = __FILE__, int line = __LINE__)
    {
        super(msg, file, line);
    }
}
