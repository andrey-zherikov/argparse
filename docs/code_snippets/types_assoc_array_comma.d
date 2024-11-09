import argparse;

struct T
{
    int[string] a;
}

T t;
assert(CLI!T.parseArgs(t, ["-a=foo=3,boo=7","-a","bar=4","baz=9"]));
assert(t == T(["foo":3,"boo":7,"bar":4,"baz":9]));
