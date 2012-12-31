
//          Copyright Ferdinand Majerech 2010 - 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Awesome2D prerenderer CLI.
module main.prerenderer;


import core.stdc.stdlib: exit;     
import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.math;
import std.stdio: writeln;
import std.typecons;

import dgamevfs._;

import awesome2d.prerenderer;
import util.unittests;
import memory.memory;



/// Exception thrown at CLI errors.
class Awesome2DCLIException : Exception 
{
    public this(string msg, string file = __FILE__, int line = __LINE__)
    {
        super(msg, file, line);
    }
}

/// Process a command line option (argument starting with --).
/// 
/// Params:  arg     = Argument to process.
///          process = Function to process the option. Takes
///                    the option and its arguments.
/// 
/// Throws:  Awesome2DCLIException if arg is not an option, and anything process() throws.
void processOption(string arg, void delegate(string, string[]) process)
{
    enforce(arg.startsWith("--"), new Awesome2DCLIException("Unknown argument: " ~ arg));
    auto argParts = arg[2 .. $].split("=");
    process(argParts[0], argParts[1 .. $]);
}

/// Print help information.
void help()
{
    // Don't ever print help twice.
    static bool helpGiven = false;
    if(helpGiven){return;}
    helpGiven = true;
    string[] help = [
        "",
        "Awesome2D prerender",
        "Pre-renders 2D lighting data from 3D models.",
        "Copyright (C) 2012-2013 Ferdinand Majerech",
        "",
        "Usage: prerender [--help] [--user_data] <command> [local-args ...]",
        "",
        "Global options:",
        "  --help                     Print this help information.",
        "  --user_data=<path>         Data directory to load configuration files from" ,
        "                             and write logs to. ./user_data/ by default.",
        "Commands:",
        "  render [opts ...] <model>  Pre-render one or more images from a model.",
        "                             Some options of this command can specify multiple",
        "                             parameters, e.g. --rotation can specify multiple",
        "                             angles. Each combination of parameters of every",
        "                             such option results in a separate image.",
        "                             The camera used for rendering will be looking at",
        "                             coordinates [0,0,0]. Camera zoom can be set by",
        "                             the --zoom option.",
        "                             The output images will be PNGs, with names based",
        "                             on model name and rendering parameters for",
        "                             each image.",
        "    Required arguments:",
        "      <model>                Filename of the model to render.",
        "                             Many formats are supported (using Assimp)",
        "                             by varying degrees. 3ds and Wavefront obj",
        "                             can always be expected to work.",
        "                             Currently, only models with normals and UV texture",
        "                             coordinates are supported.",
        "    Local options:",
        "      --rotation=<angles>    Rotation of the model around its Z axis in degrees.",
        "                             This is the direction the object is facing",
        "                             in a game. Multiple values can be specified,",
        "                             separated by commas, rendering an image for each",
        "                             orientation. E.g; '--rotation=0,90,180,270' will",
        "                             render the model in 4 facings.",
        "                             Default: '0,45,90,135,180,225,270,315'",
        "      --width=<pixels>       Width of the rendered images in pixels.",
        "                             This doesn't affect the area viewed by the camera.",
        "                             Use --zoom for that.",
        "                             Default: '64'",
        "      --height=<pixels>      Height of the rendered images in pixels.",
        "                             This doesn't affect the area viewed by the camera.",
        "                             Use --zoom for that.",
        "                             Default: '48'",
        "      --angle=<degrees>      Vertical angle of the camera in degrees.",
        "                             45 is plain isometric; 30 is common in many",
        "                             RTS's; 90 is top-down.",
        "                             Default: '45'",
        "      --texture=<filename>   Texture to use with the model. Must be in PNG",
        "                             format. A placeholder texture will be used",
        "                             if no texture is specified.",
        "                             This texture is used for the diffuse layer.",
        "                             It doesn't affect the output when rendering other",
        "                             data.",
        "      --zoom=<zoomfactor>    Camera zoom. Greater values are 'closer', rendering",
        "                             a smaller area. Use this if the model is too",
        "                             large to fit the rendered images or very small.",
        "                             Default: '0.08'",
        "      --layer=<layers>       Data 'layers' that should be rendered, separated",
        "                             by commas. Different layers can contain different",
        "                             data, e.g. color or normals.",
        "                             Data for each layer is rendered into a separate",
        "                             image.",
        "                             Supported layer types: 'diffuse' (texture color),",
        "                             'normal' (world space normals)",
        "                             Default: 'diffuse'",
        "    Example:",
        "      prerender render --texture=box.png --width=48 --height=20 box.obj",
        "                             Renders model box.obj with texture box.png with the",
        "                             default 8 rotations and a 45 degree vertical angle.",
        "                             The rendered images will be 48x20 pixels. Only the",
        "                             default (diffuse) layer will be rendered. This will",
        "                             produce 8 files named box_diffuse_0.png, ",
        "                             box_diffuse_45.png, ... , box_diffuse_315.png ."
        ];
    foreach(line; help) {writeln(line);}
}

/// Parses Awesome2D CLI commands, composes them into an action to execute, and executes it.
struct Awesome2DCLI
{
private:
    // Name of the user (read-write) data directory.
    string userDirectoryName = "./user_data";

    // Current command line argument processing function.
    //
    // Parses one command line argument.
    // 
    // In the beginning, this is the function to process global arguments.
    // When a command is encountered, it is set to that command's 
    // local arguments parser function.
    //
    // May throw Awesome2DCLIException or ConvException.
    void delegate(string) processArg_;

    // Action to execute (determined by command line arguments).
    //
    // This is the "main()" of the command being executed.
    // The returned int will be returned by main().
    //
    // May not throw.
    int delegate() action_;

    // Directory to read configuration files from and write logs to.
    StackDir utilDir_;

    // Directory to write output files to.
    VFSDir outputDir_;

    // Arguments of the "render" command.
    struct
    {
        // Rotation angles to render the model at, in degrees.
        float[] rotationAngles_ =
            [0.0f, 45.0f, 90.0f, 135.0f, 180.0f, 225.0f, 270.0f, 315.0f];

        // Width of the rendered sprites.
        int renderWidth = 64;

        // Height of the rendered sprites.
        int renderHeight = 48;

        // File name of the model to render.
        string modelFileName = null;

        // File name of the texture to use.
        string textureFileName = null;

        // Vertical angle from which we're looking at the model, in degrees.
        //
        // 45 is isometric, 30 is common in many RTSs and RPGs. 90 is top-down.
        float verticalAngle = 45.0f;

        // Camera zoom. Greater is "closer".
        float zoom = 0.08f;

        // Layers specifying data to render.
        string[] layers = ["diffuse"];
    }

public:
    /// Construct an Awesome2DCLI with specified command-line arguments and parse them.
    this(string[] cliArgs)
    {
        processArg_ = &globalOrCommand;
        foreach(arg; cliArgs[1 .. $]) {processArg_(arg);}
    }

    /// Execute the action specified by command line arguments.
    int execute()
    {
        try
        {
            //Config/log directory.
            auto userFS = new FSDir("user_data", userDirectoryName, Yes.writable);
            //Create userFS if it doesn't exist.
            userFS.create();

            auto userStack = new StackDir("user_data");
            utilDir_   = new StackDir("root");

            auto userMain = userFS.dir("main");
            userMain.create();
            userStack.mount(userMain);
            utilDir_.mount(userStack);

            outputDir_ = new FSDir("outputDir", ".", Yes.writable);

            memory.memory.outputDir = utilDir_;
        }
        catch(VFSException e)
        {
            writeln("Failed due to a file system error "
                    "(maybe user data directory is missing?): ", e.msg);
            return -1;
        }
        if(action_ is null)
        {
            writeln("No command given");
            help();
            return -1;
        }

        return action_();
    }

private:
    // Parses local options for the "render" command.
    void localRender(string arg)
    {
        // The only non-option argument is the model name.
        if(!arg.startsWith("--"))
        {
            enforce(modelFileName is null,
                    new Awesome2DCLIException("Specifying model filename more than once"));
            modelFileName = arg;
            return;
        }
        processOption(arg, (opt, args){
        enforce(!args.empty, 
                new Awesome2DCLIException("--" ~ opt ~ " needs an argument"));

        switch(opt)
        {
            case "rotation":
                rotationAngles_ = args[0].split(",").map!(to!float).array;
                break;
            case "width":  
                renderWidth  = to!int(args[0]);
                enforce(renderWidth > 0, new Awesome2DCLIException("Invalid --width parameter"));
                break;
            case "height": 
                renderHeight = to!int(args[0]);
                enforce(renderHeight > 0, new Awesome2DCLIException("Invalid --height parameter"));
                break;
            case "angle":
                verticalAngle = to!float(args[0]);
                break;
            case "texture":
                textureFileName = args[0];
                break;
            case "zoom":
                zoom = to!float(args[0]);
                enforce(zoom != 0, new Awesome2DCLIException("Can't set --zoom to 0"));
                break;
            case "layer":
                layers = args[0].split(",");
                foreach(layer; layers)
                {
                    enforce(["diffuse", "normal"].canFind(layer),
                            new Awesome2DCLIException("Unknown render layer: " ~ layer));
                }
                break;
            default:
                throw new Awesome2DCLIException("Unrecognized render option: --" ~ opt);
        }
        });
    }

    // Parse a command. Sets up command state and switches to its option parser function.
    void command(string arg)
    {
        switch (arg)
        {
            case "render":
                processArg_ = &localRender;
                action_ = ()
                {
                    if(modelFileName is null)
                    {
                        writeln("\nNo model file name specified.");
                        help();
                        return -1;
                    }
                    try
                    {
                        auto prerender = 
                            new Prerenderer(utilDir_, outputDir_, 
                                            renderWidth, renderHeight, 
                                            modelFileName, textureFileName);
                        writeln("Initialized prerender...");
                        scope(exit){clear(prerender);}
                        RenderParams params;
                        params.width         = renderWidth;
                        params.height        = renderHeight;
                        params.verticalAngle = verticalAngle;
                        params.zoom          = zoom;
                        // One image per rotation per layer
                        foreach(rot; rotationAngles_)
                        {
                            params.rotation = rot;
                            foreach(layer; layers)
                            {
                                params.layer = layer;
                                prerender.prerender(params);
                            }
                        }
                    }
                    catch(StartupException e)
                    {
                        writeln("prerender failed to start: ", e.msg);
                        return -1;
                    }
                    return 0;
                };
                break;
            default: 
                throw new Awesome2DCLIException("Unknown command: " ~ arg);
        }
    }

    // Parse a global option or command.
    void globalOrCommand(string arg)
    {
        // Command
        if(!arg.startsWith("--")) 
        {
            command(arg);
            return;
        }

        // Global option
        processOption(arg, (opt, args){
        switch(opt)
        {
            case "help":  help(); return;
            case "user_data":
                enforce(!args.empty,
                        new Awesome2DCLIException("Option --user_data needs an argument (directory)"));
                userDirectoryName = args[0];
                break;
            default:
                throw new Awesome2DCLIException("Unrecognized global option: --" ~ opt);
        }
        });
    }
}

/// Program entry point.
int main(string[] args)
{
    memory.memory.suspendMemoryDebugRecording = false;

    runUnitTests();

    try{return Awesome2DCLI(args).execute();}
    catch(ConvException e)
    {
        writeln("String conversion error. Maybe a CLI argument is in incorrect format?\n" ~
                "ERROR: ", e.msg);
        return -1;
    }
    catch(Awesome2DCLIException e)
    {
        writeln("ERROR: ", e.msg);
        return -1;
    }
}
