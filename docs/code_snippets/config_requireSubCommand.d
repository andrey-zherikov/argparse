import argparse;

struct cmd1 {}
struct cmd2 {}

struct T
{
    SubCommand!(cmd1, cmd2) cmd;
}

enum Config cfg = { requireSubCommand: true };

T t;

// parsing fails because no subcommand is provided in the command line
assert(!CLI!(cfg, T).parseArgs(t, []));

assert(CLI!(cfg, T).parseArgs(t, ["cmd1"]));
assert(t == T(typeof(T.cmd)(cmd1.init)));

assert(CLI!(cfg, T).parseArgs(t, ["cmd2"]));
assert(t == T(typeof(T.cmd)(cmd2.init)));
