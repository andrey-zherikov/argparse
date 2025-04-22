import argparse;

struct Params1
{
    @PositionalArgument(0)
    string firstName;

    @PositionalArgument(1, "lastName")
    string arg;
}

struct Params2
{
    @PositionalArgument
    string firstName;

    @PositionalArgument
    string arg;
}
