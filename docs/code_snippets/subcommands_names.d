import argparse;

@Command("minimum", "min")
struct min {}
@Command("maximum", "max")
struct max {}

struct T
{
    int[] n;  // common argument for all subcommands

    SubCommand!(min, max) cmd;
}

enum Config config = { variadicNamedArgument:true };

T t;

assert(CLI!(config, T).parseArgs(t, ["minimum","-n","1","2","3"]));
assert(t == T([1,2,3],typeof(T.cmd)(min.init)));

t = T.init;
assert(CLI!(config, T).parseArgs(t, ["max","-n","4","5","6"]));
assert(t == T([4,5,6],typeof(T.cmd)(max.init)));
