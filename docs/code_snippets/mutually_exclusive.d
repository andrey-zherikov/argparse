import argparse;

struct T
{
    @MutuallyExclusive()
    {
        string a;
        string b;
    }
}

T t;

// One of them or no argument is allowed
assert(CLI!T.parseArgs(t, ["-a","a"]));
assert(CLI!T.parseArgs(t, ["-b","b"]));
assert(CLI!T.parseArgs(t, []));

// Both arguments or no argument is not allowed
assert(!CLI!T.parseArgs(t, ["-a","a","-b","b"]));
