import argparse;

@(Command("MYPROG")
.Description("custom description")
.Epilog("custom epilog")
)
struct T
{
    @(ArgumentGroup("group1").Description("group1 description"))
    {
        @NamedArgument
        {
            string a;
            string b;
        }
        @PositionalArgument string p;
    }

    @(ArgumentGroup("group2").Description("group2 description"))
    @NamedArgument
    {
        string c;
        string d;
    }
    @PositionalArgument string q;
}

T t;
CLI!T.parseArgs(t, ["-h"]);
