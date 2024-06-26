import argparse;

struct T
{
    @(NamedArgument.Counter)
    int v;
}

enum Config cfg = { bundling: true };

T t;
assert(CLI!(cfg, T).parseArgs(t, ["-vv","-v"]));
assert(t == T(3));
