import argparse;

struct T
{
    enum Fruit {
        apple,
        @ArgumentValue("no-apple","noapple")
        noapple
    };

    Fruit a;
}

T t;
assert(CLI!T.parseArgs(t, ["-a=no-apple"]));
assert(t == T(T.Fruit.noapple));

assert(CLI!T.parseArgs(t, ["-a","noapple"]));
assert(t == T(T.Fruit.noapple));
