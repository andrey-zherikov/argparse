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

    int result = prog.cmd.match!(
        (.max)
        {
            import std.algorithm: maxElement;
            return prog.numbers.maxElement(0);
        },
        (.min)
        {
            import std.algorithm: minElement;
            return prog.numbers.minElement(0);
        },
        (.sum)
        {
            import std.algorithm: sum;
            return prog.numbers.sum;
        }
    );

    writeln("result = ", result);

    return 0;
});