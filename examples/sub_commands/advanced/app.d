import argparse;
import std.stdio: writeln;

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

@(Command       // use "sum" (type name) as a command name
.Usage("%(PROG) [<number>...]")
.Description(() => "Print sum of the numbers")
)
struct sum
{
    @PositionalArgument
    int[] numbers;
}

@(Command("minimum", "min")
.Usage(() => "%(PROG) [<number>...]")
.Description(() => "Print the minimal number across provided")
.ShortDescription(() => "Print the minimum")
)
struct MinCmd
{
    @PositionalArgument
    int[] numbers;
}

@(Command("maximum", "max")
.Usage("%(PROG) [<number>...]")
.Description("Print the maximal number across provided")
.ShortDescription("Print the maximum")
)
struct MaxCmd
{
    @PositionalArgument
    int[] numbers;
}

@(Command.Description("Description of main program"))
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
    SubCommand!(sum, MinCmd, MaxCmd) cmd;
}


// This mixin defines standard main function that parses command line and calls the provided function:
mixin CLI!Program.main!((prog)
{
    static assert(is(typeof(prog) == Program));

    writeln("prog = ", prog);

    prog.cmd.match!(
        (MaxCmd cmd)
        {
            import std.algorithm: maxElement;
            writeln("max = ", cmd.numbers.filter(prog.filter).maxElement(int.min));
        },
        (MinCmd cmd)
        {
            import std.algorithm: minElement;
            writeln("min = ", cmd.numbers.filter(prog.filter).minElement(int.max));
        },
        (sum cmd)
        {
            import std.algorithm: sum;
            writeln("sum = ", cmd.numbers.filter(prog.filter).sum);
        }
    );

    return 0;
});