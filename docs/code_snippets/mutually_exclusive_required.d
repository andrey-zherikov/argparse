import argparse;

struct T
{
    @(MutuallyExclusive.Required)
    {
        string a;
        string b;
    }
}

T t;

// Either argument is allowed
assert(CLI!T.parseArgs(t, ["-a","a"]));
assert(CLI!T.parseArgs(t, ["-b","b"]));

// Both or no arguments are not allowed
assert(!CLI!T.parseArgs(t, ["-a","a","-b","b"]));
assert(!CLI!T.parseArgs(t, []));
