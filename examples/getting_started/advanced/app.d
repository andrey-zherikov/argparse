import argparse;
import argparse.ansi;

struct Advanced
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

    // Enums can have a value that is not an identifier
    enum Enum {
        @ArgumentValue("value1","value-1","value.1")
        value1,
        value2,
    }
    @NamedArgument
    Enum choice;

    // Custom types can also be used with custon parsing function
    struct CustomType {
        double d;
    }
    @(NamedArgument.Parse!((string value) { import std.conv: to; return CustomType(value.to!double); }))
    CustomType custom;

    @(NamedArgument.Description(green.bold.underline("Colorize")~" the output. If value is omitted then '"~red("always")~"' is used."))
    static auto color = ansiStylingArgument;
}

// Customize prsing config
auto config()
{
    Config cfg;

    cfg.helpStyle.programName = blue.onYellow;
    cfg.helpStyle.namedArgumentName = bold.italic.cyan.onRed;

    return cfg;
}

// This mixin defines standard main function that parses command line and calls the provided function:
mixin CLI!(config(), Advanced).main!((args, unparsed)
{
    // 'args' has 'Advanced' type
    static assert(is(typeof(args) == Advanced));

    // unparsed arguments has 'string[]' type
    static assert(is(typeof(unparsed) == string[]));

    // do whatever you need
    import std.stdio: writeln;
    args.writeln;
    writeln("Unparsed args: ", unparsed);

    // use actual styling mode to print output
    auto style = Advanced.color == Config.StylingMode.on ? red.onWhite : noStyle;
    writeln(style("Styling mode: "), Advanced.color);
    assert(Advanced.color == Config.StylingMode.on || Advanced.color == Config.StylingMode.off);

    return 0;
});