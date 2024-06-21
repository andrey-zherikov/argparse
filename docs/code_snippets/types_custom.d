import argparse;

struct Value
{
    string a;
}
struct T
{
    @(NamedArgument.Parse!((string s) { return Value(s); }))
    Value s;
}

T t;
assert(CLI!T.parseArgs(t, ["-s","foo"]));
assert(t == T(Value("foo")));