//          Copyright Ferdinand Majerech 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/// Awesome2D 2D lighting demo.
module demo.demo;


import std.algorithm;
import std.stdio;

import dgamevfs._;

import color;
import platform.platform;
import platform.sdl2platform;
import util.yaml;
import video.exceptions;
import video.renderer;
import video.sdl2glrenderer;

/// Exception thrown when Awesome2D fails to start.
class StartupException : Exception 
{
    public this(string msg, string file = __FILE__, int line = __LINE__)
    {
        super(msg, file, line);
    }
}

/// Awesome2D 2D lighting demo.
class Demo
{
private:
    // Directory to load data and configuration from.
    VFSDir dataDir_;

    /// Platform used for user input.
    Platform platform_;
    // Renderer.
    Renderer renderer_;
    // Container managing the renderer and its dependencies.
    RendererContainer rendererContainer_;
    // Main config file (YAML).
    YAMLNode config_;
    // Continue running?
    bool continue_ = true;

public:
    /// Construct Demo with specified data directory.
    ///
    /// Throws:  StartupException on failure.
    this(VFSDir dataDir)
    {
        dataDir_ = dataDir;
        writeln("Initializing Demo...");

        initConfig();
        initPlatform();
        writeln("Initialized Platform");
        scope(failure){destroyPlatform();}
        //TODO resolution from config
        initRenderer(800, 600);
        writeln("Initialized Video");
        scope(failure){destroyRenderer();}
    }

    // Deinitialize the demo.
    ~this()
    {
        writeln("Destroying Demo...");
        destroyRenderer();
        destroyPlatform();
    }

    /// Run the main loop of the demo.
    void run()
    {
        ulong iterations = 0;
        scope(failure)
        {
            writeln("Failure in Demo main loop, iteration ", iterations);
        }

        platform_.key.connect(&keyHandler);

        while(platform_.run() && continue_)
        {
            bool frame(Renderer renderer)
            {
                //TODO
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
            auto configFile = dataDir_.file("config.yaml");
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
            platform_ = new SDL2Platform();
        }
        catch(PlatformException e)
        {
            platform_ = null;
            throw new StartupException("Failed to initialize platform: " ~ e.msg);
        }
    }

    /// Initialize the renderer. Throws StartupException on failure.
    void initRenderer(const uint width, const uint height)
    {
        try{rendererContainer_ = new RendererContainer();}
        catch(RendererInitException e)
        {
            throw new StartupException("Failed to initialize renderer "
                                       "dependencies: " ~ e.msg);
        }

        // Load config options (not sure if anyone will use this...).
        auto video       = config_["video"];
        const depth      = video["depth"].as!uint;
        const format     = depth == 16 ? ColorFormat.RGB_565 : ColorFormat.RGBA_8;
        const fullscreen = video["fullscreen"].as!bool;

        if(![16, 32].canFind(depth))
        {
            writeln("Unsupported video mode depth: ", depth,
                    " - falling back to 32bit");
        }

        renderer_ = rendererContainer_.produce!SDL2GLRenderer
                    (width, height, format, fullscreen);

        // Failed to initialize renderer, clean up.
        if(renderer_ is null)
        {
            rendererContainer_.destroy();
            clear(rendererContainer_);
            throw new StartupException("Failed to initialize renderer.");
        }
    }

    /// Destroy the renderer.
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

    /// Exit the demo.
    void exit(){continue_ = false;}

    /// Process keyboard input.
    /// 
    /// Params:  state   = State of the key.
    ///          key     = Keyboard key.
    ///          unicode = Unicode value of the key.
    void keyHandler(KeyState state, Key key, dchar unicode)
    {
        if(state == KeyState.Pressed) switch(key)
        {
            case Key.Escape: exit(); break;
            default: break;
        }
    }
}
