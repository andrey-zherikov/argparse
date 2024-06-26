import argparse;

struct T
{
    bool a;
    bool b;
    string c;
}

enum Config cfg = { bundling: true };

T t;

assert(CLI!(cfg, T).parseArgs(t, ["-ab"]));
assert(t == T(true, true));

assert(CLI!(cfg, T).parseArgs(t, ["-abc=foo"]));
assert(t == T(true, true, "foo"));

assert(CLI!(cfg, T).parseArgs(t, ["-a","-bc=foo"]));
assert(t == T(true, true, "foo"));

assert(CLI!(cfg, T).parseArgs(t, ["-a","-bcfoo"]));
assert(t == T(true, true, "foo"));
