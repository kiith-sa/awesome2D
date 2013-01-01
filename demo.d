
//          Copyright Ferdinand Majerech 2010 - 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Awesome2D demo CLI.
module main.demo;


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

import demo.demo;
import memory.memory;
import util.unittests;
import util.yaml;



/// Exception thrown at CLI errors.
class DemoCLIException : Exception 
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
/// Throws:  DemoCLIException if arg is not an option, and anything process() throws.
void processOption(string arg, void delegate(string, string[]) process)
{
    enforce(arg.startsWith("--"), new DemoCLIException("Unknown argument: " ~ arg));
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
        "Awesome2D demo",
        "Demonstration of advanced 2D lighting",
        "Copyright (C) 2012-2013 Ferdinand Majerech",
        "",
        "Usage: demo [--help] [--user_data]",
        "",
        "Global options:",
        "  --help                     Print this help information.",
        "  --data=<path>              Data directory to load configuration files from" ,
        "                             and write logs to. ./demo_data/ by default.",
        ];
    foreach(line; help) {writeln(line);}
}

/// Parses Awesome2D CLI commands, composes them into an action to execute, and executes it.
struct DemoCLI
{
private:
    // Name of the user (read-write) data directory.
    string userDirectoryName = "./demo_data";

    // Current command line argument processing function.
    //
    // Parses one command line argument.
    //
    // May throw DemoCLIException or ConvException.
    void delegate(string) processArg_;

    // Action to execute (determined by command line arguments).
    //
    // This is the "main()" of the demo.
    // The returned int will be returned by main().
    //
    // May not throw.
    int delegate() action_;

    // Directory to read configuration files from and write logs to.
    StackDir dataDir_;

public:
    /// Construct an DemoCLI with specified command-line arguments and parse them.
    this(string[] cliArgs)
    {
        processArg_ = &global;
        action_     = &actionDemo;
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
            dataDir_   = new StackDir("root");

            auto userMain = userFS.dir("main");
            userMain.create();
            userStack.mount(userMain);
            dataDir_.mount(userStack);

            memory.memory.outputDir = dataDir_;
        }
        catch(VFSException e)
        {
            writeln("Failed due to a file system error "
                    "(maybe the data directory is missing?): ", e.msg);
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
    // Parse a global option.
    void global(string arg)
    {
        // Command
        if(!arg.startsWith("--")) 
        {
            throw new DemoCLIException("Unknown command line argument: " ~ arg);
        }

        // Global option
        processOption(arg, (opt, args){
        switch(opt)
        {
            case "help":  help(); return;
            case "data":
                enforce(!args.empty,
                        new DemoCLIException("Option --data needs an argument (directory)"));
                userDirectoryName = args[0];
                break;
            default:
                throw new DemoCLIException("Unrecognized global option: --" ~ opt);
        }
        });
    }

    // Main function of the demo.
    //
    // Returns:  0 on success, -1 on failure.
    int actionDemo()
    {
        try
        {
            auto demo = new Demo(dataDir_);
            writeln("Initialized demo...");
            demo.run();
        }
        catch(StartupException e)
        {
            writeln("demo failed to start: ", e.msg);
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

    try{return DemoCLI(args).execute();}
    catch(ConvException e)
    {
        writeln("String conversion error. Maybe a CLI argument is in incorrect format?\n" ~
                "ERROR: ", e.msg);
        return -1;
    }
    catch(DemoCLIException e)
    {
        writeln("ERROR: ", e.msg);
        return -1;
    }
}
