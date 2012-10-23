
//          Copyright Ferdinand Majerech 2010 - 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


///Program entry point.
module main.demo;


import core.stdc.stdlib: exit;     
import std.stdio: writeln;
import std.typecons;

import dgamevfs._;

import awesome2d.awesome2d;
import formats.cli;
import util.unittests;
import memory.memory;

void main(string[] args)
{
    memory.memory.suspendMemoryDebugRecording = false;

    runUnitTests();
    
    writeln("Started main()...");
    //will add -h/--help and generate usage info by itself
    auto cli = new CLI();
    cli.description = "Awesome2D demo\n"
                      "Demonstration of advanced 2D lighting techniques.\n"
                      "Copyright (C) 2012 Ferdinand Majerech";
    cli.epilog = "Report errors at <kiithsacmp@gmail.com> (in English, Czech or Slovak).";

    string root = "./data";
    string user = "./user_data";

    //Root data and user data MUST be specified at startup
    cli.addOption(CLIOption("root_data").shortName('R').target(&root));
    cli.addOption(CLIOption("user_data").shortName('U').target(&user));

    if(!cli.parse(args)){return;}

    scope(exit) writeln("Main exit");
    try
    {
        auto rootFS    = new FSDir("root_data", root, No.writable);
        auto userFS    = new FSDir("user_data", user, Yes.writable);
        //Create userFS if it doesn't exist. rootFS not existing is an error.
        userFS.create();

        auto rootStack = new StackDir("root_data");
        auto userStack = new StackDir("user_data");
        auto gameDir   = new StackDir("root");

        rootStack.mount(rootFS.dir("main"));
        auto userMain = userFS.dir("main");
        userMain.create();
        userStack.mount(userMain);
        gameDir.mount(rootStack);
        gameDir.mount(userStack);

        writeln("Initialized VFS...");
        memory.memory.gameDir = gameDir;

        auto demo = new Awesome2D(gameDir);
        writeln("Initialized Awesome2D...");
        scope(exit){clear(demo);}
        writeln("Going to run Awesome2D...");
        demo.run();
    }
    catch(StartupException e)
    {
        writeln("Demo failed to start: ", e.msg);
        exit(-1);
    }
    catch(VFSException e)
    {
        writeln("Failed due to a file system error "
                "(maybe data directory is missing?): ", e.msg);
        exit(-1);
    }
}
