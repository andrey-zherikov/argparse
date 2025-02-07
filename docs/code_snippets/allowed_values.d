import argparse;

struct T
{
    @(NamedArgument.AllowedValues("apple","pear","banana"))
    string fruit;
}

T t;
assert(CLI!T.parseArgs(t, ["--fruit", "apple"]));
assert(t == T("apple"));

// "kiwi" is not allowed
assert(!CLI!T.parseArgs(t, ["--fruit", "kiwi"]));
