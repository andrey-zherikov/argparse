import argparse;

struct T
{
    @(NamedArgument.AllowNoValue(10)) int a;
    @(NamedArgument.ForceNoValue(20)) int b;
}

T t;
assert(CLI!T.parseArgs(t, ["-a"]));
assert(t.a == 10);

assert(CLI!T.parseArgs(t, ["-b"]));
assert(t.b == 20);

assert(CLI!T.parseArgs(t, ["-a","30"]));
assert(t.a == 30);

assert(!CLI!T.parseArgs(t, ["-b","30"])); // Unrecognized arguments: ["30"]