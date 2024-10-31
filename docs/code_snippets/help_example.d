import argparse;

@(Command("MYPROG")
.Description("custom description")
.Epilog("custom epilog")
)
struct T
{
    @NamedArgument  string s;
    @(NamedArgument.Placeholder("VALUE"))  string p;

    @(NamedArgument.Hidden)  string hidden;

    enum Fruit { apple, pear };
    @(NamedArgument("f","fruit").Required.Description("This is a help text for fruit. Very very very very very very very very very very very very very very very very very very very long text")) Fruit f;

    @(NamedArgument.AllowedValues!([1,4,16,8])) int i;

    @(PositionalArgument(0).Description("This is a help text for param0. Very very very very very very very very very very very very very very very very very very very long text")) string param0;
    @(PositionalArgument(1).AllowedValues!(["q","a"])) string param1;
}

T t;
CLI!T.parseArgs(t, ["-h"]);
