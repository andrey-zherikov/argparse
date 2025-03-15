import argparse;

struct T
{
    string a;
    string baz;
}

enum Config cfg = { shortNamePrefix: "+", longNamePrefix: "==" };

T t;
assert(CLI!(cfg, T).parseArgs(t, ["+a","foo","==baz","BAZZ"]));
assert(t == T("foo","BAZZ"));
