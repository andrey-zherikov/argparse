import argparse;

struct T
{
    int[] a;
}

enum Config cfg = { arraySep: ',' };

T t;
assert(CLI!(cfg, T).parseArgs(t, ["-a=1,2,3","-a","4,5"]));
assert(t == T([1,2,3,4,5]));
