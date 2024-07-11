import argparse;
import std.stdio: writeln;


struct sum {}
struct min {}
struct max
{
    string foo; // --foo argument
}

struct Program
{
    int[] numbers;  // --numbers argument

    // Default!T marks T as default command
    SubCommand!(sum, min, Default!max) cmd;
}

// This mixin defines standard main function that parses command line and calls the provided function:
mixin CLI!Program.main!((prog)
{
    static assert(is(typeof(prog) == Program));

    writeln("prog = ", prog);

    prog.cmd.match!(
        (.max m)
        {
            import std.algorithm: maxElement;
            writeln("max = ", prog.numbers.maxElement(int.min), " foo = ", m.foo);
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