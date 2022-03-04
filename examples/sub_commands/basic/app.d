import argparse;
import std.stdio: writeln;
import std.sumtype: SumType, match;


struct sum
{
    @PositionalArgument(0)
    int[] numbers;

    int opCall() const
    {
        import std.algorithm: sum;

        return numbers.sum;
    }
}

struct min
{
    @PositionalArgument(0)
    int[] numbers;

    int opCall() const
    {
        import std.algorithm: minElement;

        return numbers.length > 0 ? numbers.minElement : 0;
    }
}

struct max
{
    @PositionalArgument(0)
    int[] numbers;

    int opCall() const
    {
        import std.algorithm: maxElement;

        return numbers.length > 0 ? numbers.maxElement : 0;
    }
}

struct Program
{
    // SumType indicates sub-command
    // name of the command is the same as a name of the type
    SumType!(sum, min, max) cmd;
}


// This mixin defines standard main function that parses command line and calls the provided function:
mixin Main.parseCLIArgs!(Program, (prog) => prog.cmd.match!((cmd)
{
    writeln(typeof(cmd).stringof," = ", cmd());

    return 0;
}));