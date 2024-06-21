import argparse;

struct T
{
    string a, b;
}

T t1;
CLI!T.parseArgs(t1, ["-a", "A", "-h", "-b", "B"]);
assert(t1 == T("A"));

enum Config cfg = { addHelp: false };

T t2;
string[] unrecognizedArgs;
CLI!(cfg, T).parseKnownArgs(t2, ["-a", "A", "-h", "-b", "B"], unrecognizedArgs);
assert(t2 == T("A","B"));
assert(unrecognizedArgs == ["-h"]);
