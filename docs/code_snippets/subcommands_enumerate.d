import argparse;

struct cmd1 {}
struct cmd2 {}
struct cmd3 {}

// This mixin defines standard main function that parses command line and calls the provided function:
mixin CLI!(cmd1, cmd2, cmd3).main!((cmd)
{
    import std.stdio;
    cmd.writeln;
});
