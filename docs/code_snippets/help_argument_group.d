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
        @PositionalArgument(0) string p;
    }

    @(ArgumentGroup("group2").Description("group2 description"))
    @NamedArgument
    {
        string c;
        string d;
    }
    @PositionalArgument(1) string q;
}

T t;
CLI!T.parseArgs(t, ["-h"]);
