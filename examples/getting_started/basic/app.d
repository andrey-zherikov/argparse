import argparse;

// If struct has no UDA then all members are named arguments
static struct Basic
{
    // Basic data types are supported:
        // --name argument
        string name;

        // --number argument
        int number;

        // --boolean argument
        bool boolean;

    // Argument can have default value if it's not specified in command line
        // --unused argument
        string unused = "some default value";


    // Enums are also supported
        enum Enum { unset, foo, boo }
        // --choice argument
        Enum choice;

    // Use array to store multiple values
        // --array argument
        int[] array;

    // Callback with no args (flag)
        // --callback argument
        void callback() {}

    // Callback with single value
        // --callback1 argument
        void callback1(string value) { assert(value == "cb-value"); }

    // Callback with zero or more values
        // --callback2 argument
        void callback2(string[] value) { assert(value == ["cb-v1","cb-v2"]); }
}

// This mixin defines standard main function that parses command line and calls the provided function:
mixin Main.parseCLIArgs!(Basic, (args)
{
    // 'args' has 'Baisc' type
    static assert(is(typeof(args) == Basic));

    // do whatever you need
    import std.stdio: writeln;
    args.writeln;
    return 0;
});

// Parser can even work at compile time
enum values = ([
    "--boolean",
    "--number","100",
    "--name","Jake",
    "--array","1","2","3",
    "--choice","foo",
    "--callback",
    "--callback1","cb-value",
    "--callback2","cb-v1","cb-v2",
].parseCLIArgs!Basic).get;

static assert(values.name     == "Jake");
static assert(values.unused   == Basic.init.unused);
static assert(values.number   == 100);
static assert(values.boolean  == true);
static assert(values.choice   == Basic.Enum.foo);
static assert(values.array    == [1,2,3]);
