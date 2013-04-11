
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
import std.path;
import std.stdio: writeln;
import std.string;
import std.typecons;

import dgamevfs._;

import prerenderer.prerenderer;
import memory.memory;
import util.unittests;
import util.yaml;



/// Exception thrown at CLI errors.
class PrerendererCLIException : Exception 
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
/// Throws:  PrerendererCLIException if arg is not an option, and anything process() throws.
void processOption(string arg, void delegate(string, string[]) process)
{
    enforce(arg.startsWith("--"), new PrerendererCLIException("Unknown argument: " ~ arg));
    auto argParts = arg[2 .. $].split("=");
    process(argParts[0], argParts[1 .. $]);
}

/// Print help information.
///
/// Params:  commandName = Name of the command used to launch the TileGenerator.
void help(string commandName)
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
        "Usage: " ~ commandName ~ " [--help] [--user_data] <command> [local-args ...]",
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
        "                             The output images will be PNGs, written to ",
        "                             a subdirectory MODELBASENAME_prerender, where",
        "                             MODELBASENAME is the name of the model without",
        "                             the file extenstion. A YAML metadata file, ",
        "                             sprite.yaml, will also be written to this directory.",
        "    Required arguments:",
        "      <model>                Filename of the model to render.",
        "                             Many formats are supported (using Assimp)",
        "                             by varying degrees. 3ds and Wavefront obj",
        "                             can always be expected to work.",
        "                             Currently, only models with normals and UV texture",
        "                             coordinates are supported.",
        "    Local options:",
        "      --rotation=<angles>     Rotation of the model around its Z axis (degrees).",
        "                              This is the direction the object is facing",
        "                              in a game. Multiple values can be specified,",
        "                              separated by commas, rendering an image for each",
        "                              orientation. E.g; '--rotation=0,90,180,270' will",
        "                              render the model in 4 facings.",
        "                              Default: '0,45,90,135,180,225,270,315'",
        "      --width=<pixels>        Width of the rendered images in pixels.",
        "                              This doesn't affect the area viewed by the camera.",
        "                              Use --zoom for that.",
        "                              Default: '64'",
        "      --height=<pixels>       Height of the rendered images in pixels.",
        "                              This doesn't affect the area viewed by the camera.",
        "                              Use --zoom for that.",
        "                              Default: '48'",
        "      --angle=<degrees>       Vertical angle of the camera in degrees.",
        "                              45 is plain isometric; 30 is common in many",
        "                              RTS's; 90 is top-down.",
        "                              Default: '45'",
        "      --texture=<filename>    Texture to use with the model. Must be in PNG",
        "                              format. A placeholder texture will be used",
        "                              if no texture is specified.",
        "                              This texture is used for the diffuse layer.",
        "                              It doesn't affect the output when rendering other",
        "                              data.",
        "      --zoom=<zoomfactor>     Camera zoom. Greater values are 'closer',",
        "                              rendering a smaller area. Use this if the model",
        "                              is too largelarge to fit the rendered images or",
        "                              very small.",
        "                              Default: '0.08'",
        "      --layer=<layers>        Data 'layers' that should be rendered, separated",
        "                              by commas. Different layers can contain different",
        "                              data, e.g. color or normals.",
        "                              Data for each layer is rendered into a separate",
        "                              image.",
        "                              Supported layer types: 'diffuse' (texture color),",
        "                              'normal' (world space normals), 'offset'",
        "                              (3D position at each pixel relative to origin)",
        "                              Default: 'diffuse'",
        "      --supersampling=<level> Level of supersampling (antialiasing) to use.",
        "                              If greater than 1, the sprite is rendered in a",
        "                              greater resolution and then downsampled.",
        "                              For example, a 64x32 sprite with supersampling of",
        "                              2 will be rendered in the resolution of 128x64 and",
        "                              then downsampled, averaging the pixels. Note that",
        "                              this will result in semi-transparent (using alpha)",
        "                              pixels on the edges of the sprite.",
        "                              This improves image quality, but requires alpha",
        "                              transparency support in the game drawing the",
        "                              sprite.",
        "                              Must not be 0.",
        "                              Note that very high values might result in",
        "                              ridiculously huge OpenGL viewports, which your",
        "                              GPU might not be able to handle. Keep it below 10",
        "                              if you can.",
        "                              Note that supersampling will only affect layers",
        "                              where it makes sense, e.g. the diffuse color, but",
        "                              not layers like normals or offsets (averaging ",
        "                              vectors would result in completely different",
        "                              lighting)",
        "                              Default: 1",
        "    Example:",
        "      " ~ commandName ~ " render '--texture=box.png' --width=48 --height=20 'box.obj'",
        "                             Renders model box.obj with texture box.png with the",
        "                             default 8 rotations and a 45 degree vertical angle.",
        "                             The rendered images will be 48x20 pixels. Only the",
        "                             default (diffuse) layer will be rendered. This will",
        "                             produce 8 files named box_diffuse_0.png, ",
        "                             box_diffuse_45.png, ... , box_diffuse_315.png ."
        ];
    foreach(line; help) {writeln(line);}
}

/// Parses Prerenderer CLI commands, composes them into an action to execute, and executes it.
struct PrerendererCLI
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
    // May throw PrerendererCLIException or ConvException.
    void delegate(string) processArg_;

    // Action to execute (determined by command line arguments).
    //
    // This is the "main()" of the command being executed.
    // The returned int will be returned by main().
    //
    // May not throw.
    int delegate() action_;

    // Name of the command used to launch the Prerenderer 
    // (usually the filename of the binary).
    string prerendererCommandName_;

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

        // Supersampling level (1 for no supersampling, 2 for 2x2, etc.).
        uint superSamplingLevel = 1;
    }

public:
    /// Construct a PrerendererCLI with specified command-line arguments and parse them.
    this(string[] cliArgs)
    {
        processArg_ = &globalOrCommand;
        prerendererCommandName_ = cliArgs[0];
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
            utilDir_ = new StackDir("root");

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
            help(prerendererCommandName_);
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
                    new PrerendererCLIException("Specifying model filename more than once"));
            modelFileName = arg;
            return;
        }
        processOption(arg, (opt, args){
        enforce(!args.empty, 
                new PrerendererCLIException("--" ~ opt ~ " needs an argument"));

        switch(opt)
        {
            case "rotation":
                rotationAngles_ = args[0].split(",").map!(to!float).array;
                break;
            case "width":  
                renderWidth  = to!int(args[0]);
                enforce(renderWidth > 0, new PrerendererCLIException("Invalid --width parameter"));
                break;
            case "height": 
                renderHeight = to!int(args[0]);
                enforce(renderHeight > 0, new PrerendererCLIException("Invalid --height parameter"));
                break;
            case "angle":
                verticalAngle = to!float(args[0]);
                break;
            case "texture":
                textureFileName = args[0];
                break;
            case "zoom":
                zoom = to!float(args[0]);
                enforce(zoom != 0, new PrerendererCLIException("Can't set --zoom to 0"));
                break;
            case "layer":
                layers = args[0].split(",");
                foreach(layer; layers)
                {
                    enforce(["diffuse", "normal", "offset"].canFind(layer),
                            new PrerendererCLIException("Unknown render layer: " ~ layer));
                }
                break;
            case "supersampling":
                superSamplingLevel = to!int(args[0]);
                enforce(superSamplingLevel > 0,
                        new PrerendererCLIException("Supersampling must not be 0"));
                break;
            default:
                throw new PrerendererCLIException("Unrecognized render option: --" ~ opt);
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
                action_ = &actionRender;
                break;
            default: 
                throw new PrerendererCLIException("Unknown command: " ~ arg);
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
            case "help":  help(prerendererCommandName_); return;
            case "user_data":
                enforce(!args.empty,
                        new PrerendererCLIException("Option --user_data needs an argument (directory)"));
                userDirectoryName = args[0];
                break;
            default:
                throw new PrerendererCLIException("Unrecognized global option: --" ~ opt);
        }
        });
    }

    // Action executed for the "render" command.
    //
    // Returns:  0 on success, -1 on failure.
    int actionRender()
    {
        if(modelFileName is null)
        {
            writeln("\nNo model file name specified.");
            help(prerendererCommandName_);
            return -1;
        }
        try
        {
            const modelBaseName = stripExtension(baseName(modelFileName));
            YAMLNode[] imagesMeta;
            outputDir_ = outputDir_.dir(modelBaseName ~ "_prerender");
            outputDir_.create();
            auto prerender = new Prerenderer(utilDir_, outputDir_,
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
                string[] layersMetaKeys;
                string[] layersMetaValues;
                params.rotation = rot;
                foreach(layer; layers)
                {
                    params.layer = layer;
                    // Supersampling makes no sense with normals or offsets.
                    params.superSamplingLevel = layer == "diffuse" ? superSamplingLevel : 1;
                    const fileName = prerender.prerender(params);
                    layersMetaKeys ~= layer;
                    layersMetaValues ~= fileName;
                }
                imagesMeta ~= YAMLNode(["zRotation", "layers"],
                                       [YAMLNode(rot), 
                                        YAMLNode(layersMetaKeys, layersMetaValues)]);
            }
            // If we had 1 unit == 1 pixel, params.width would be projection width.
            // Our projection width is 1.0f / zoom. Multiplying offsets by this scale maps 
            // offsets to 1 pixel == 1 unit.
            const offsetScale = renderWidth / (1.0f / zoom);

            // Write YAML metadata about the sprite.
            string[] spriteMetaKeys;
            YAMLNode[] spriteMetaValues;
            spriteMetaKeys   ~= "verticalAngle";
            spriteMetaValues ~= YAMLNode(verticalAngle);
            spriteMetaKeys   ~= "size";
            spriteMetaValues ~= YAMLNode([renderWidth, renderHeight]);
            spriteMetaKeys   ~= "offsetScale";
            spriteMetaValues ~= YAMLNode(offsetScale);
            prerender.sceneMeta(spriteMetaKeys, spriteMetaValues);
            auto spriteMeta = YAMLNode(spriteMetaKeys, spriteMetaValues);
            YAMLNode meta = YAMLNode(["sprite", "images"], [spriteMeta, YAMLNode(imagesMeta)]);

            string fileName = "sprite.yaml";
            try
            {
                auto file = outputDir_.file(fileName);
                saveYAML(file, meta);
            }
            catch(VFSException e)
            {
                writeln("Failed to write sprite metadata file ", fileName, ": ", e.msg);
                return -1;
            }
            catch(YAMLException e)
            {
                writeln("Failed to write sprite metadata file ", fileName, ": ", e.msg);
                return -1;
            }
        }
        catch(StartupException e)
        {
            writeln("prerender failed to start: ", e.msg);
            return -1;
        }
        return 0;
    };
}

/// Program entry point.
int main(string[] args)
{
    memory.memory.suspendMemoryDebugRecording = false;

    runUnitTests();

    try{return PrerendererCLI(args).execute();}
    catch(ConvException e)
    {
        writeln("String conversion error. Maybe a CLI argument is in incorrect format?\n" ~
                "ERROR: ", e.msg);
        return -1;
    }
    catch(PrerendererCLIException e)
    {
        writeln("ERROR: ", e.msg);
        return -1;
    }
}
