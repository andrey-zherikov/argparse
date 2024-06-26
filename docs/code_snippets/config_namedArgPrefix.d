import argparse;

struct T
{
    string a;
    string baz;
}

enum Config cfg = { namedArgPrefix: '+' };

T t;
assert(CLI!(cfg, T).parseArgs(t, ["+a","foo","++baz","BAZZ"]));
assert(t == T("foo","BAZZ"));
