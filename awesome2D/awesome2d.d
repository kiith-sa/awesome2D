
//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// "Main class" of the Awesome2D demo.
module awesome2d.awesome2d;

import std.algorithm;
import std.stdio;

import dgamevfs._;

import color;
import platform.platform;
import platform.sdlplatform;
import util.yaml;
import video.exceptions;
import video.renderer;
import video.sdlglrenderer;


/// Thrown when the program fails to start.
class StartupException : Exception 
{
    public this(string msg, string file = __FILE__, int line = __LINE__)
    {
        super(msg, file, line);
    }
}


/// "Main class" of the Awesome2D demo.
class Awesome2D
{
private:
    /// Platform used for user input.
    Platform platform_;
    /// Renderer.
    Renderer renderer_;
    /// Container managing the renderer and its dependencies.
    RendererContainer rendererContainer_;
  
    /// When set to false, the main loop ends.
    bool continue_ = true;

    /// Root directory of the virtual file system.
    VFSDir gameDir_;
    /// Main config file (YAML).
    YAMLNode config_;

public:
    /// Construct Awesome2D.
    ///
    /// Params: gameDir = Root directory of the virtual file system.
    ///
    /// Throws: StartupException on failure.
    this(VFSDir gameDir)
    {
       gameDir_ = gameDir;
       writeln("Initializing Awesome2D...");
       scope(failure){writeln("Initializing Awesome2D...");}
  
       initConfig();
       writeln("Initialized Config");
       initPlatform();
       writeln("Initialized Platform");
       scope(failure){destroyPlatform();}
       initRenderer();
       writeln("Initialized Video");
       scope(failure){destroyRenderer();}
    }

    /// Destroy Awesome2D.
    ~this()
    {
       writeln("Destroying Awesome2D...");
       destroyRenderer();
       destroyPlatform();
    }

    /// Run the main loop of the demo.
    void run()
    {
        ulong iterations = 0;
        scope(failure)
        {
            writeln("Failure in Awesome2D main loop, iteration ", iterations);
        }

        platform_.key.connect(&keyHandler);

        while(platform_.run() && continue_)
        {
           bool frame(Renderer renderer)
           {
              renderer.testDrawTriangle(); 
              return true;
           }
           renderer_.renderFrame(&frame);
           ++iterations;
        }
    }

private:
    /// Load configuration from YAML.
    void initConfig()
    {
        try
        {
            auto configFile = gameDir_.file("config.yaml");
            config_ = loadYAML(configFile);
        }
        catch(YAMLException e)
        {
            throw new StartupException("Failed to load main config file: " ~ e.msg);
        }
        catch(VFSException e)
        {
            throw new StartupException("Failed to load main config file: " ~ e.msg);
        }
    }

    /// Initialize the Platform subsystem. Throws StartupException on failure.
    void initPlatform()
    {
        try
        {
            platform_ = new SDLPlatform();
        }
        catch(PlatformException e)
        {
            platform_ = null;
            throw new StartupException("Failed to initialize platform: " ~ e.msg);
        }
    }

    /// Initialize the renderer. Throws StartupException on failure.
    void initRenderer()
    {
        try{rendererContainer_ = new RendererContainer();}
        catch(RendererInitException e)
        {
            throw new StartupException("Failed to initialize renderer "
                                       "dependencies: " ~ e.msg);
        }

        auto video       = config_["video"];
        const width      = video["width"].as!uint;
        const height     = video["height"].as!uint;
        const depth      = video["depth"].as!uint;
        const format     = depth == 16 ? ColorFormat.RGB_565 : ColorFormat.RGBA_8;
        const fullscreen = video["fullscreen"].as!bool;

        if(![16, 32].canFind(depth))
        {
            writeln("Unsupported video mode depth: ", depth,
                    " - falling back to 32bit");
        }
        renderer_ = rendererContainer_.produce!SDLGLRenderer
                    (width, height, format, fullscreen);
        if(renderer_ is null)
        {
            rendererContainer_.destroy();
            clear(rendererContainer_);
            throw new StartupException("Failed to initialize renderer.");
        }
    }

    /// Destroy the renderer,
    void destroyRenderer()
    {
        //Renderer might be already destroyed in exceptional circumstances
        //such as a failed renderer reset.
        if(renderer_ is null){return;}
        rendererContainer_.destroy();
        clear(rendererContainer_);
        renderer_ = null;
    }

    /// Destroy the Platform subsystem.
    void destroyPlatform()
    {
        clear(platform_);
        platform_ = null;
    }

    /**
     * Process keyboard input.
     *
     * Params:  state   = State of the key.
     *          key     = Keyboard key.
     *          unicode = Unicode value of the key.
     */
    void keyHandler(KeyState state, Key key, dchar unicode)
    {
        if(state == KeyState.Pressed) switch(key)
        {
            case Key.Escape: exit(); break;
            default: break;
        }
    }

    ///Exit Awesome2D.
    void exit(){continue_ = false;}
}
