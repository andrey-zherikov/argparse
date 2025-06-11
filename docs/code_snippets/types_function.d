import argparse;

struct T
{
    int a_;
    string[] b_;
    string[][] c_;

    @NamedArgument
    {
        void a() { a_++; }
        void b(string s) { b_ ~= s; }
        void c(string[] s) { c_ ~= s; }
    }
}

T t;
assert(CLI!T.parseArgs(t, ["-a","-b","1","-c","q,w",
                           "-a","-b","2","-c","e,r",
                           "-a","-b","3","-c","t,y",]));
assert(t == T(3, ["1","2","3"], [["q","w"],["e","r"],["t","y"]]));
