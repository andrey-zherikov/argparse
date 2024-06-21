import argparse;

struct T
{
    @RequiredTogether()
    {
        string a;
        string b;
    }
}

T t;

// Both or no argument is allowed
assert(CLI!T.parseArgs(t, ["-a","a","-b","b"]));
assert(CLI!T.parseArgs(t, []));

// Only one argument is not allowed
assert(!CLI!T.parseArgs(t, ["-a","a"]));
assert(!CLI!T.parseArgs(t, ["-b","b"]));
