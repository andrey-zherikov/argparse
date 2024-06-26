import argparse;
import argparse.ansi;

struct T
{
    string a, b;
}

enum Config cfg = { styling: { programName: blue, argumentName: green.italic } };

T t;
CLI!(cfg, T).parseArgs(t, ["-a", "A", "-h", "-b", "B"]);
assert(t == T("A"));
