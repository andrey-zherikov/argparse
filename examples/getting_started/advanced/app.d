import argparse;

static struct Advanced
{
    // Positional arguments are required by default
    @PositionalArgument(0)
    string name;

    // Named arguments can be attributed in bulk (parentheses can be omitted)
    @NamedArgument
    {
        string unused = "some default value";
        int number;
        bool boolean;
    }

    // Named argument can have custom or multiple names
    @NamedArgument("apple","appl")
    int apple;

    @NamedArgument(["b","banana","ban"])
    int banana;

    @NamedArgument
    static auto color = ansiStylingArgument;
}

// This mixin defines standard main function that parses command line and calls the provided function:
mixin CLI!Advanced.main!((args, unparsed)
{
    // 'args' has 'Advanced' type
    static assert(is(typeof(args) == Advanced));

    // unparsed arguments has 'string[]' type
    static assert(is(typeof(unparsed) == string[]));

    // do whatever you need
    import std.stdio: writeln;
    args.writeln;
    writeln("Unparsed args: ", unparsed);
    return 0;
});