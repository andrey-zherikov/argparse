import argparse;
import std.stdio: writeln;


struct sum {}
struct min {}
struct max {}

struct Program
{
    int[] numbers;  // --numbers argument

    // name of the command is the same as a name of the type
    SubCommand!(sum, min, max) cmd;
}

// This mixin defines standard main function that parses command line and calls the provided function:
mixin CLI!Program.main!((prog)
{
    static assert(is(typeof(prog) == Program));

    writeln("prog = ", prog);

    prog.cmd.matchCmd!(
        (.max)
        {
            import std.algorithm: maxElement;
            writeln("max = ", prog.numbers.maxElement(int.min));
        },
        (.min)
        {
            import std.algorithm: minElement;
            writeln("min = ", prog.numbers.minElement(int.max));
        },
        (.sum)
        {
            import std.algorithm: sum;
            writeln("sum = ", prog.numbers.sum);
        }
    );

    return 0;
});