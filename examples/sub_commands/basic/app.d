import argparse;
import std.stdio: writeln;


struct sum
{
    int[] numbers;  // --numbers argument
}

struct min
{
    int[] numbers;  // --numbers argument
}

struct max
{
    int[] numbers;  // --numbers argument
}

int main_(max cmd)
{
    import std.algorithm: maxElement;

    writeln("max = ", cmd.numbers.maxElement);

    return 0;
}

int main_(min cmd)
{
    import std.algorithm: minElement;

    writeln("min = ", cmd.numbers.minElement);

    return 0;
}

int main_(sum cmd)
{
    import std.algorithm: sum;

    writeln("sum = ", cmd.numbers.sum);

    return 0;
}

// This mixin defines standard main function that parses command line and calls the provided function:
mixin CLI!(sum, min, max).main!main_;
