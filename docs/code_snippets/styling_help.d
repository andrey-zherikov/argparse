import argparse;
import argparse.ansi;

struct T
{
    @(NamedArgument("red").Description(bold.underline("Colorize the output:")~" make everything "~red("red")))
    bool red_;
}

T t;
CLI!T.parseArgs(t, ["-h"]);
