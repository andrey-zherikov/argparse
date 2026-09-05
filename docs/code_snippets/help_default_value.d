import argparse;
import std.typecons: Nullable;

struct T
{
    enum Mode { fast, slow }

    @(NamedArgument.Description("path to config file"))
    string config = "/etc/app.conf";

    @(NamedArgument.Description("mode to use"))
    Mode mode;

    @(NamedArgument.Description("tags to filter by"))
    string[] tags;

    // default value is provided in runtime
    @(NamedArgument.Description("number of threads")
     .PrintDefaultValueInHelp(() => Nullable!string("number of CPUs")))
    int threads;

    // default value is not printed even though it's not empty
    @(NamedArgument.Description("output file").PrintDefaultValueInHelp(false))
    string output = "out.txt";
}

T t;
CLI!T.parseArgs(t, ["-h"]);
