import argparse;

struct T
{
    enum Fruit { apple, pear };

    Fruit a;
}

T t;
assert(CLI!T.parseArgs(t, ["-a","apple"]));
assert(t == T(T.Fruit.apple));

assert(CLI!T.parseArgs(t, ["-a=pear"]));
assert(t == T(T.Fruit.pear));
