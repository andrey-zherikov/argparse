import argparse;
import std.stdio: writeln;
import std.sumtype: SumType, match;

enum Filter { none, even, odd };

auto filter(R)(R numbers, Filter filt)
{
    alias isOdd = n => (n&1);
    alias isEven = n => !isOdd(n);

    alias func = (n)
    {
        final switch(filt)
        {
            case Filter.none:   return true;
            case Filter.even:   return isEven(n);
            case Filter.odd :   return isOdd(n);
        }
    };

    import std.algorithm: filter;
    return numbers.filter!func;
}

@(Command("sum")
.Usage("%(PROG) [<number>...]")
.Description(() => "Print sum of the numbers")
)
struct SumCmd
{
    @PositionalArgument(0)
    int[] numbers;
}

@(Command("minimum", "min")
.Usage(() => "%(PROG) [<number>...]")
.Description(() => "Print the minimal number across provided")
.ShortDescription(() => "Print the minimum")
)
struct MinCmd
{
    @PositionalArgument(0)
    int[] numbers;
}

@(Command("maximum", "max")
.Usage("%(PROG) [<number>...]")
.Description("Print the maximal number across provided")
.ShortDescription("Print the maximum")
)
struct MaxCmd
{
    @PositionalArgument(0)
    int[] numbers;
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
mixin CLI!Program.main!((prog)
{
    static assert(is(typeof(prog) == Program));

    int result = prog.cmd.match!(
        (MaxCmd cmd)
        {
            import std.algorithm: maxElement;
            return cmd.numbers.filter(prog.filter).maxElement(0);
        },
        (MinCmd cmd)
        {
            import std.algorithm: minElement;
            return cmd.numbers.filter(prog.filter).minElement(0);
        },
        (SumCmd cmd)
        {
            import std.algorithm: sum;
            return cmd.numbers.filter(prog.filter).sum;
        }
    );

    writeln("result = ", result);

    return 0;
});