
//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// "Main class" of the Awesome2D prerenderer.
module awesome2d.prerenderer;

import std.algorithm;
import std.path;
import std.stdio;
import std.string;

import dgamevfs._;

import awesome2d.scene;
import color;
import platform.platform;
import platform.sdl2platform;
import util.yaml;
import video.exceptions;
import video.renderer;
import video.sdl2glrenderer;


/// Thrown when the program fails to start.
class StartupException : Exception 
{
    public this(string msg, string file = __FILE__, int line = __LINE__)
    {
        super(msg, file, line);
    }
}

/// Parameters of a single pre-rendering call.
struct RenderParams
{
    /// Rotation of the model, in degrees.
    float rotation = 0;
    /// Vertical angle from which we're looking at the model, in degrees.
    float verticalAngle = 45.0f;
    /// Width of the rendered area in pixels.
    uint width  = 800;
    /// Height of the rendered area in pixels.
    uint height = 600;
    /// Zoom of the camera. Greater is "closer".
    float zoom = 1.0f;
    /// Render layer (data) to render. E.g. diffuse, normal, offset.
    string layer = "diffuse";
}

/// "Main class" of the Awesome2D prerenderer.
class Prerenderer
{
private:
    /// Platform used for user input.
    Platform platform_;
    /// Renderer.
    Renderer renderer_;
    /// Container managing the renderer and its dependencies.
    RendererContainer rendererContainer_;

    /// Root directory of the virtual file system.
    VFSDir utilDir_;
    /// Directory to write output files to.
    VFSDir outputDir_;
    /// Main config file (YAML).
    YAMLNode config_;

    /// Graphics scene we're rendering.
    Scene scene_;

    /// File name of the rendered model.
    string modelFileName_;

public:
    /// Construct the prerenderer.
    ///
    /// Params: utilDir         = Directory for configuration files and logging output.
    ///         outputDir       = Directory to write output files to.
    ///         width           = Video mode width in pixels.
    ///         height          = Video mode height in pixels.
    ///         modelFileName   = File name of the model to render.
    ///         textureFileName = File name of the texture to use. Can be null.
    ///
    /// Throws: StartupException on failure.
    this(VFSDir utilDir, VFSDir outputDir, const uint width, const uint height,
         string modelFileName, string textureFileName)
    {
       utilDir_   = utilDir;
       outputDir_ = outputDir;
       writeln("Initializing Prerenderer...");
       scope(failure){writeln("Initializing Awesome2D...");}
       modelFileName_ = modelFileName;

       initConfig();
       initPlatform();
       writeln("Initialized Platform");
       scope(failure){destroyPlatform();}
       initRenderer(width, height);
       writeln("Initialized Video");
       scope(failure){destroyRenderer();}
       initScene(modelFileName, textureFileName);
       scope(failure){destroyScene();}
    }

    /// Destroy the prerenderer.
    ~this()
    {
       writeln("Destroying Prerenderer...");
       destroyScene();
       destroyRenderer();
       destroyPlatform();
    }

    /// Get metadata about the graphics rendered in the scene as YAML.
    @property void sceneMeta(ref string[] keys, ref YAMLNode[] values) @safe
    {
        scene_.sceneMeta(keys, values);
    }

    /// Render the scene with specified parameters and write the result to an image file.
    ///
    /// Output filename will be based on the model filename and render parameters.
    ///
    /// May not throw, although file output might fail, in which case an
    /// error will be written to stdout.
    ///
    /// Returns:  Filename of the output file.
    string prerender(ref const RenderParams params)
    {
        const modelBaseName = stripExtension(baseName(modelFileName_));
        string fileName = 
            format("%s_%s_%s.png", modelBaseName, params.layer, params.rotation);

        // Contains all rendering done in a single frame. 
        //
        // Returns true when the frame is done.
        bool frame(Renderer renderer)
        {
            import formats.image;
            import image;
            import memory.memory;
            import video.framebuffer;


            // Create FBO to draw to.
            ColorFormat colorFormat;
            switch(params.layer)
            {
                case "diffuse": colorFormat = ColorFormat.RGBA_8; break;
                case "normal":  colorFormat = ColorFormat.RGB_8;  break;
                case "offset":  colorFormat = ColorFormat.RGB_8;  break;
                default:        assert(false, "Unknown color format " ~ params.layer);
            }

            auto fbo = renderer_.createFrameBuffer(params.width, params.height, colorFormat);
            scope(exit){free(fbo);}

            // Bind FBO and draw.
            {
                fbo.bind();
                scope(exit){fbo.release();}
                fbo.clear();
                scene_.draw(params);
            }

            // Write to an image file.
            Image fboImage;
            fbo.toImage(fboImage);
            try
            {
                auto file = outputDir_.file(fileName);
                writeImage(fboImage, file);
            }
            catch(VFSException e)
            {
                writeln("Failed to render ", fileName, ": ", e.msg);
            }
            catch(ImageFileException e)
            {
                writeln("Failed to render ", fileName, ": ", e.msg);
            }

            // Draw once more to view the output.
            scene_.draw(params);

            return true;
        }
        renderer_.renderFrame(&frame);

        return fileName;
    }

private:
    /// Load configuration from YAML.
    void initConfig()
    {
        try
        {
            auto configFile = utilDir_.file("config.yaml");
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

    /// Initialize the graphics scene.
    ///
    /// Params:  modelFileName   = Filename of the model to render.
    ///          textureFileName = Filename of the texture to use with the model.
    ///
    /// Throws:  StartupException on an initialization failure 
    ///          (e.g. if the model could not be loaded).
    void initScene(const string modelFileName, const string textureFileName)
    {
        try
        {
            scene_ = new Scene(outputDir_, renderer_, modelFileName, textureFileName);
        }
        catch(SceneInitException e)
        {
            throw new StartupException("Failed to initialize scene: " ~ e.msg);
        }
    }

    /// Destroy the graphics scene.
    void destroyScene()
    {
        clear(scene_);
        scene_ = null;
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
}
