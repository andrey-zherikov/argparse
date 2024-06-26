import argparse;

struct T
{
    string a;
}

auto arguments = [ "-a", "A", "-c", "C" ];

T result;
assert(CLI!T.parseKnownArgs(result, arguments));
assert(result == T("A"));
assert(arguments == ["-c", "C"]);
