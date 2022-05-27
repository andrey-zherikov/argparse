import argparse;
import std.stdio: writeln;
import std.sumtype: SumType, match;


struct sum {}
struct min {}
struct max
{
    string foo; // --foo argument
}

struct Program
{
    int[] numbers;  // --numbers argument

    // SumType indicates sub-command
    // Default!T marks T as default command
    SumType!(sum, min, Default!max) cmd;
}

// This mixin defines standard main function that parses command line and calls the provided function:
mixin CLI!Program.main!((prog)
{
    static assert(is(typeof(prog) == Program));

    prog.cmd.match!(
        (.max m)
        {
            import std.algorithm: maxElement;
            writeln("max = ", prog.numbers.maxElement(0), " foo = ", m.foo);
        },
        (.min)
        {
            import std.algorithm: minElement;
            writeln("min = ", prog.numbers.minElement(0));
        },
        (.sum)
        {
            import std.algorithm: sum;
            writeln("sum = ", prog.numbers.sum);
        }
    );

    return 0;
});