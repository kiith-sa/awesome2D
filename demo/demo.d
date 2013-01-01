//          Copyright Ferdinand Majerech 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/// Awesome2D 2D lighting demo.
module demo.demo;

import dgamevfs._;

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

public:
    /// Construct Demo with specified data directory.
    this(VFSDir dataDir)
    {
        dataDir_ = dataDir;
        //TODO
    }

    void run()
    {
        //TODO
    }
}
