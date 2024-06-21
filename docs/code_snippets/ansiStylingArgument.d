import argparse;

struct T
{
    static auto color = ansiStylingArgument;
}

T t;
CLI!T.parseArgs(t, ["-h"]);

// This is a way to detect whether `--color` argument was specified in the command line
// Note that 'autodetect' is converted to either 'on' or 'off'
assert(CLI!T.parseArgs(t, ["--color"]));
assert(t.color);

assert(CLI!T.parseArgs(t, ["--color=always"]));
assert(t.color);

assert(CLI!T.parseArgs(t, ["--color=never"]));
assert(!t.color);
