import argparse;

struct min {}
struct max {}
struct sum {}

struct T
{
    int[] n;  // common argument for all subcommands

    // name of the subcommand is the same as a name of the type by default
    SubCommand!(min, max, sum) cmd;
}

enum Config config = { variadicNamedArgument:true };

T t;

assert(CLI!(config, T).parseArgs(t, ["min","-n","1","2","3"]));
assert(t == T([1,2,3],typeof(T.cmd)(min.init)));

t = T.init;
assert(CLI!(config, T).parseArgs(t, ["max","-n","4","5","6"]));
assert(t == T([4,5,6],typeof(T.cmd)(max.init)));

t = T.init;
assert(CLI!(config, T).parseArgs(t, ["sum","-n","7","8","9"]));
assert(t == T([7,8,9],typeof(T.cmd)(sum.init)));
