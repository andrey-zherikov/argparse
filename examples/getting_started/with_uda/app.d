import argparse;

struct Example
{
    // Positional arguments are required by default
    @PositionalArgument(0)
    string name;

    // Named arguments can be attributed in bulk (parentheses can be omitted)
    @NamedArgument
    {
        // '--number' argument
        int number;

        // '--boolean' argument
        bool boolean;

        // Argument can have default value if it's not specified in command line
        // '--unused' argument
        string unused = "some default value";
    }

    // Enums are also supported
    enum Enum { unset, foo, boo }

    // '--choice' argument
    @NamedArgument
    Enum choice;

    // Named argument can have specific or multiple names
    @NamedArgument("apple","appl")
    int apple;

    @NamedArgument("b","banana","ban")
    int banana;
}

// This mixin defines standard main function that parses command line and calls the provided function:
mixin CLI!Example.main!((args)
{
    // 'args' has 'Example' type
    static assert(is(typeof(args) == Example));

    // do whatever you need
    import std.stdio: writeln;
    args.writeln;
    return 0;
});