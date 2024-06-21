import argparse;

struct T
{
    @NamedArgument
    string a;
    @NamedArgument
    string b;

    @PositionalArgument(0)
    string[] args;
}

T t;
assert(CLI!T.parseArgs(t, ["-a","A","--","-b","B"]));
assert(t == T("A","",["-b","B"]));
