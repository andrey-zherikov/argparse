import argparse;

struct T
{
    @NamedArgument string a;
    @PositionalArgument string b;
    @PositionalArgument string[] c;
}

enum Config cfg = { endOfNamedArgs: "---" };

T t;
assert(CLI!(cfg, T).parseArgs(t, ["B","-a","foo","---","--","-a","boo"]));
assert(t == T("foo","B",["--","-a","boo"]));
