import argparse;

struct T
{
    string[] param;
}

enum Config cfg = { caseSensitive: false };

T t;
assert(CLI!(cfg, T).parseArgs(t, ["--param","1","--PARAM","2","--PaRaM","3"]));
assert(t == T(["1","2","3"]));
