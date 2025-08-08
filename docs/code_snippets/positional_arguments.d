import argparse;

struct Params1
{
    @PositionalArgument
    string firstName;

    @PositionalArgument("lastName")
    string arg;
}

struct Params2
{
    @PositionalArgument
    string firstName;

    @PositionalArgument
    string arg;
}
