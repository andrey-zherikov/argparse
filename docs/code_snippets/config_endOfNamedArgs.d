import argparse;

struct T
{
    @NamedArgument string a;
    @PositionalArgument(0) string b;
    @PositionalArgument(1) string[] c;
}

enum Config cfg = { endOfNamedArgs: "---" };

T t;
assert(CLI!(cfg, T).parseArgs(t, ["B","-a","foo","---","--","-a","boo"]));
assert(t == T("foo","B",["--","-a","boo"]));
