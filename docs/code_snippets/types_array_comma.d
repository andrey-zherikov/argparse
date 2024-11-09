import argparse;

struct T
{
    int[] a;
}

T t;
assert(CLI!T.parseArgs(t, ["-a=1,2,3","-a","4","5"]));
assert(t == T([1,2,3,4,5]));
