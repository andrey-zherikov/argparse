import argparse;

struct T
{
    @(NamedArgument.NumberOfValues(1,3))
    int[] a;
    @(NamedArgument.NumberOfValues(2))
    int[] b;
}

T t;
assert(CLI!T.parseArgs(t, ["-a","1","2","3","-b","4","5"]));
assert(t == T([1,2,3], [4,5]));
