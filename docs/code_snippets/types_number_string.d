import argparse;

struct T
{
    int i;
    uint u;
    double f;
    string s;
    wstring w;
    dstring d;
}

T t;
assert(CLI!T.parseArgs(t, ["-i","-5","-u","8","-f","12.345","-s","sss","-w","www","-d","ddd"]));
assert(t == T(-5,8,12.345,"sss","www","ddd"));
