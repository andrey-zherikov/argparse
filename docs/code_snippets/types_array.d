import argparse;

struct T
{
    int[]   a;
    int[][] b;
}

T t;
assert(CLI!T.parseArgs(t, ["-a=1,2,3","-a","4,5"]));
assert(t == T([1,2,3,4,5]));

assert(CLI!T.parseArgs(t, ["-b=1,2,3","-b","4,5"]));
assert(t.b == [[1,2,3],[4,5]]);
