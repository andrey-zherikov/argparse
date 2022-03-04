import argparse;
import std.stdio: writeln;
import std.sumtype: SumType, match;

enum Filter { even, odd };

auto filter(R)(R numbers, Filter filt)
{
    alias isOdd = n => (n&1);
    alias isEven = n => !isOdd(n);

    alias func = (n)
    {
        final switch(filt)
        {
            case Filter.even:   return isEven(n);
            case Filter.odd :   return isOdd(n);
        }
    };

    import std.algorithm: filter;
    return numbers.filter!func;
}

@(Command("sum")
.Usage("%(PROG) [<number>...]")
.Description("Print sum of the numbers")
.ShortDescription("Print the sum")
)
struct SumCmd
{
    @PositionalArgument(0)
    int[] numbers;

    int opCall(Filter filter) const
    {
        import std.algorithm: sum;

        return numbers.filter(filter).sum;
    }
}

@(Command("min")
.Usage("%(PROG) [<number>...]")
.Description("Print the minimal number across provided")
.ShortDescription("Print the minimum")
)
struct MinCmd
{
    @PositionalArgument(0)
    int[] numbers;

    int opCall(Filter filter) const
    {
        import std.algorithm: minElement;

        return numbers.length > 0 ? numbers.filter(filter).minElement : 0;
    }
}

@(Command("max")
.Usage("%(PROG) [<number>...]")
.Description("Print the maximal number across provided")
.ShortDescription("Print the maximum")
)
struct MaxCmd
{
    @PositionalArgument(0)
    int[] numbers;

    int opCall(Filter filter) const
    {
        import std.algorithm: maxElement;

        return numbers.length > 0 ? numbers.filter(filter).maxElement : 0;
    }
}

struct Program
{
    // Common arguments
    @ArgumentGroup("Common arguments")
    {
        @NamedArgument
        Filter filter;
    }

    // Sub-command
    // name of the command is the same as a name of the type
    @SubCommands
    SumType!(SumCmd, MinCmd, MaxCmd) cmd;
}


// This mixin defines standard main function that parses command line and calls the provided function:
mixin Main.parseCLIArgs!(Program, (prog) => prog.cmd.match!((cmd)
{
    writeln(typeof(cmd).stringof," = ", cmd(prog.filter));

    return 0;
}));