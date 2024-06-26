import argparse;

struct cmd1 {}
struct cmd2 {}
struct cmd3 {}

struct T
{
    // name of the subcommand is the same as a name of the type by default
    SubCommand!(cmd1, cmd2, cmd3) cmd;
}

T t;

assert(CLI!T.parseArgs(t, []));
assert(t == T.init);

assert(CLI!T.parseArgs(t, ["cmd1"]));
assert(t == T(typeof(T.cmd)(cmd1.init)));

assert(CLI!T.parseArgs(t, ["cmd2"]));
assert(t == T(typeof(T.cmd)(cmd2.init)));

assert(CLI!T.parseArgs(t, ["cmd3"]));
assert(t == T(typeof(T.cmd)(cmd3.init)));
