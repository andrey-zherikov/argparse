import argparse;

struct T
{
    @(RequiredTogether.Required)
    {
        string a;
        string b;
    }
}

T t;

// Both arguments are allowed
assert(CLI!T.parseArgs(t, ["-a","a","-b","b"]));

// Single argument or no argument is not allowed
assert(!CLI!T.parseArgs(t, ["-a","a"]));
assert(!CLI!T.parseArgs(t, ["-b","b"]));
assert(!CLI!T.parseArgs(t, []));
