import argparse;

struct T
{
    @(NamedArgument.Counter)
    int v;
}

T t;
assert(CLI!T.parseArgs(t, ["-v","-v","-v"]));
assert(t == T(3));
