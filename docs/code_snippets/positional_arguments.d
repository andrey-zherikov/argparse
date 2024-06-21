import argparse;

struct Params
{
    @PositionalArgument(0)
    string firstName;

    @PositionalArgument(1, "lastName")
    string arg;
}
