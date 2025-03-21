import argparse;

struct T
{
    string[] param;
    string[] s;
}

enum Config cfg = { caseSensitiveShortName: false, caseSensitiveLongName: false };

T t;
assert(CLI!(cfg, T).parseArgs(t, ["--param","1","--PARAM","2","--PaRaM","3","-s","a","-S","b"]));
assert(t == T(["1","2","3"],["a","b"]));
