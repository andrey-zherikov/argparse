import argparse;

struct T
{
    string[] a;
}

enum Config cfg = { assignChar: ':' };

T t;
assert(CLI!(cfg, T).parseArgs(t, ["-a:1","-a:2","-a:3"]));
assert(t == T(["1","2","3"]));
