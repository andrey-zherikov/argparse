import argparse;

struct T
{
    @(PositionalArgument(0, "a").Optional)
    string a = "not set";

    @(NamedArgument.Required)
    int b;
}

T t;
assert(CLI!T.parseArgs(t, ["-b", "4"]));
assert(t == T("not set", 4));
