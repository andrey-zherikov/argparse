import argparse;

struct T
{
    int[string] a;
}

enum Config cfg = { assignKeyValueChar: ':' };

T t;
assert(CLI!(cfg, T).parseArgs(t, ["-a=A:1","-a=B:2,C:3"]));
assert(t == T(["A":1,"B":2,"C":3]));
