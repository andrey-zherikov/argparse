import argparse;

struct T
{
    string[] a;
}

T t1;
assert(CLI!T.parseArgs(t1, ["-a=1:2:3","-a","4"]));
assert(t1 == T(["1:2:3","4"]));

enum Config cfg = { valueSep: ':' };

T t2;
assert(CLI!(cfg, T).parseArgs(t2, ["-a=1:2:3","-a","4"]));
assert(t2 == T(["1","2","3","4"]));
