import argparse;

struct T
{
    int[string] a;
}

T t;
assert(CLI!T.parseArgs(t, ["-a=foo=3","-a","boo=7"]));
assert(t == T(["foo":3,"boo":7]));
