//          Copyright Ferdinand Majerech 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Generates tiles with various shapes from a texture.
module tilegenerator.tilegenerator;


import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.file;
import std.path;
import std.process;
import std.stdio;

import demo.tileshape;


/// Exception thrown at CLI errors.
class TileGeneratorCLIException : Exception 
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
/// Throws:  TileGeneratorCLIException if arg is not an option, and anything process() throws.
void processOption(string arg, void delegate(string, string[]) process)
{
    enforce(arg.startsWith("--"), new TileGeneratorCLIException("Unknown argument: " ~ arg));
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
        "Awesome2D tile generator",
        "Creates tiles for the Awesome2D demo from a texture.",
        "Copyright (C) 2012-2013 Ferdinand Majerech",
        "",
        "Usage: " ~ commandName ~ " [--help] <command> [local-args ...]",
        "Global options:",
        "  --help                     Print this help information.",
        "Commands:",
        "  auto [opts ...] <texture>  Automatically generate multiple tile shapes",
        "                             using specified texture. The texture is split",
        "                             into 9 equal parts - the center is used for the",
        "                             'flat' shape, the part above the center is used",
        "                             for 'northeast' shapes, the left-top part for",
        "                             'east', left part for 'south-east', and so on.",
        "                             The cells and camera will match the demo;",
        "                             30 degree vertical angle, 128x64 cell with 32",
        "                             pixels for one height layer. World-space extents",
        "                             of the cell are 2x2x0.8 . Diffuse, normal and ",
        "                             offset data will be generated.",
        "                             The output will be in directory ",
        "                             './TEXTUREBASENAME_tile', where TEXTUREBASENAME",
        "                             is the texture filename without extension.",
        "                             Each tile shape will be in its own subdirectory",
        "                             named by the shape name, for example",
        "                             ./TEXTUREBASENAME_tile/flat for the flat shape.",
        "    Required arguments:",
        "      <texture>              Texture to use generate tile shapes from. Only",
        "                             the PNG file format is supported at the moment.",
        "    Local options:",
        "      --shapes=<shapes>      Tile shapes to generate, separated by commas",
        "                             (all by default).",
        "                             Default: 'flat,slope-ne,slope-se,slope-nw,slope-sw,",
        "                                       cliff-n,cliff-s,cliff-w,cliff-e,",
        "                                       slope-n-top,slope-s-top,slope-w-right,",
        "                                       slope-e-right,slope-n-bottom,slope-s-bottom,",
        "                                       slope-w-left, slope-e-left'",
        "    Example:",
        "      " ~ commandName ~ " auto grass.png",
        "                             Generate all tile shapes using texture 'grass.png'.",
        "                             The generated tiles will be written to directory",
        "                             ./grass_tile"
        ];

    foreach(line; help) {writeln(line);}
}

/// Command line interface of the TileGenerator (and really the whole implementation).
struct TileGeneratorCLI
{
private:
    // Current command line argument processing function.
    //
    // Parses one command line argument.
    // 
    // In the beginning, this is the function to process global arguments.
    // When a command is encountered, it is set to that command's 
    // local arguments parser function.
    //
    // May throw TileGeneratorCLIException or ConvException.
    void delegate(string) processArg_;

    // Action to execute (determined by command line arguments).
    //
    // This is the "main()" of the command being executed.
    // The returned int will be returned by main().
    //
    // May not throw.
    int delegate() action_;

    // Name of the directory with tile shape 3D models used by the "auto" command.
    string dataDirectoryName_ = "./tilegenerator_data";

    // Tile shapes to generate for the "auto" command (all tile shapes by default).
    string[] autoTileShapes_ = tileShapeStrings;

    // File name of the texture to use.
    string textureFileName_;

    // Name of the command used to launch the TileGenerator 
    // (usually the filename of the binary).
    string tileGeneratorCommandName_;

public:
    /// Construct a TileGeneratorCLI with specified command-line arguments and parse them.
    this(string[] cliArgs)
    {
        processArg_ = &globalOrCommand;
        tileGeneratorCommandName_ = cliArgs[0];
        foreach(arg; cliArgs[1 .. $]) {processArg_(arg);}
    }

    /// Execute the action specified by command line arguments.
    int execute()
    {
        if(action_ is null)
        {
            writeln("ERROR: No command given.");
            help(tileGeneratorCommandName_);
            return -1;
        }

        return action_();
    }

private:
    // Parse a command. Sets up command state and switches to its option parser function.
    void command(string arg)
    {
        switch (arg)
        {
            case "auto":
                processArg_ = &localAuto;
                action_     = &actionAuto;
                break;
            default: 
                throw new TileGeneratorCLIException("Unknown command: " ~ arg);
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
            case "help":  help(tileGeneratorCommandName_); return;
            default:
                throw new TileGeneratorCLIException("Unrecognized global option: --" ~ opt);
        }
        });
    }

    // Parses local options for the "auto" command.
    void localAuto(string arg)
    {
        enforce(arg.startsWith("--") || textureFileName_ is null,
                new TileGeneratorCLIException("Unknown argument: " ~ arg));
        // The only non-option argument is the texture name.
        if(!arg.startsWith("--"))
        {
            textureFileName_ = arg;
            return;
        }

        processOption(arg, (opt, args){
        enforce(!args.empty, 
                new TileGeneratorCLIException("--" ~ opt ~ " needs an argument"));

        switch(opt)
        {
            // Tile shapes to generate.
            case "shapes":
                foreach(shape; args)
                {
                    enforce(isTileShapeString(shape),
                            new TileGeneratorCLIException("Not a tile shape: " ~ shape));
                }
                autoTileShapes_ = args;
                break;
            default:
                throw new TileGeneratorCLIException("Unrecognized auto option: --" ~ opt);
        }
        });
    }

    // Action executed for the "render" command.
    //
    // Returns:  0 on success, 1 on failure.
    int actionAuto()
    {
        if(textureFileName_ is null)
        {
            writeln("ERROR: No texture specified.");
            return 1;
        }

        // Run the prerenderer "render" command with specified arguments.
        void runPrerenderer(string[] args)
        {
            string prerendererName;
            // Find the prerenderer binary.
            // Look for ./prerenderer-release, ./prerenderer, etc.
            foreach(build; ["-release", "-debug", "-no-contracts", ""])
            {
                prerendererName = "./prerenderer" ~ build;
                if(prerendererName.exists && prerendererName.isFile){break;}
            }
            const command = ([prerendererName, "render"] ~ args).join(" ");

            // Run the command itself.
            try
            {
                writeln("\nRunning prerenderer command:\n ", command);
                // Not using output (stdout of command) yet,
                // might be useful later for debugging.
                const output = shell(command);
            }
            catch(ErrnoException e)
            {
                writeln("\nPrerenderer command failed: " ~ e.msg);
            }
        }

        // Prerender each specified tile shape.
        try foreach(shape; autoTileShapes_)
        {
            // Example prerenderer command:
            //
            //./prerenderer-debug render --texture=tileDefault.png --width=128 --height=96 
            //                           --angle=30 --rotation=0 --layer=diffuse,normal,offset 
            //                           --zoom=0.355 tilegenerator_data/slope-e-right.obj

            string[] args;
            args ~= "\"--texture=" ~ textureFileName_ ~ "\"";
            args ~= "--width=128";
            args ~= "--height=96";
            args ~= "--angle=30";
            args ~= "--rotation=0";
            args ~= "--layer=diffuse,normal,offset";
            args ~= "--zoom=0.355";
            args ~= "tilegenerator_data/" ~ shape ~ ".obj";

            runPrerenderer(args);

            // Move the prerenderer output to tile output directory.
            // E.g. slope-n-top_prerender to grass01_tile/slope-n-top
            const outDirName = "./" ~ textureFileName_.stripExtension.baseName ~ "_tile/" ~ shape;
            if(!outDirName.exists){mkdirRecurse(outDirName);}
            const prerenderDirName = "./" ~ shape ~ "_prerender";
            foreach(string fileName; dirEntries(prerenderDirName, SpanMode.depth))
            {
                copy(fileName, 
                     outDirName ~ "/" ~ fileName[prerenderDirName.length + 1 .. $]);
            }
            rmdirRecurse(prerenderDirName);
        }
        catch(FileException e)
        {
            writeln("ERROR: Tile generation failed: ", e.msg);
            return 1;
        }

        return 0;
    }
}


/// Program entry point.
int main(string[] args)
{
    try{return TileGeneratorCLI(args).execute();}
    catch(ConvException e)
    {
        writeln("String conversion error. Maybe a CLI argument is in incorrect format?\n" ~
                "ERROR: ", e.msg);
        return -1;
    }
    catch(TileGeneratorCLIException e)
    {
        writeln("ERROR: ", e.msg);
        return -1;
    }
}
