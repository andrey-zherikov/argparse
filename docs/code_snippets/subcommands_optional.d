import argparse;

struct cmd1 {}
struct cmd2 {}
struct cmd3 {}

struct T
{
    // subcommand can be omitted even though it is required by the config below
    @Optional
    SubCommand!(cmd1, cmd2, cmd3) cmd;
}

enum Config cfg = { requireSubCommand: true };

T t;

assert(CLI!(cfg, T).parseArgs(t, []));
assert(t == T.init);

assert(CLI!(cfg, T).parseArgs(t, ["cmd1"]));
assert(t == T(typeof(T.cmd)(cmd1.init)));

assert(CLI!(cfg, T).parseArgs(t, ["cmd2"]));
assert(t == T(typeof(T.cmd)(cmd2.init)));

assert(CLI!(cfg, T).parseArgs(t, ["cmd3"]));
assert(t == T(typeof(T.cmd)(cmd3.init)));
