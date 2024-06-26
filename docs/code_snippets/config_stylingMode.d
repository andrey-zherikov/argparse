import argparse;

struct T
{
    string a, b;
}

enum Config cfg = { stylingMode: Config.StylingMode.off };

T t;
CLI!(cfg, T).parseArgs(t, ["-a", "A", "-h", "-b", "B"]);
assert(t == T("A"));
