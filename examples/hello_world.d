// THIS CONTENT SHOULD BE IN SYNC WITH README

unittest
{
    import argparse;

    static struct Params
    {
        // Positional arguments are required by default
        @PositionalArgument(0)
        string name;

        // Named argments are optional by default
        @NamedArgument("unused")
        string unused = "some default value";

        // Numeric types are converted automatically
        @NamedArgument("num")
        int number;

        // Boolean flags are supported
        @NamedArgument("flag")
        bool boolean;

        // Enums are also supported
        enum Enum { unset, foo, boo }
        @NamedArgument("enum")
        Enum enumValue;

        // Use array to store multiple values
        @NamedArgument("array")
        int[] array;

        // Callback with no args (flag)
        @NamedArgument("cb")
        void callback() {}

        // Callback with single value
        @NamedArgument("cb1")
        void callback1(string value) { assert(value == "cb-value"); }

        // Callback with zero or more values
        @NamedArgument("cb2")
        void callback2(string[] value) { assert(value == ["cb-v1","cb-v2"]); }
    }

    // Define your main function that takes an object with parsed CLI arguments
    int myMain(Params args)
    {
        // do whatever you need
        return 0;
    }

version(with_main)
{
    // Main function should call the parser and drop argv[0]
    int main(string[] argv)
    {
        return parseCLIArgs!Params(argv[1..$], &myMain);
    }
}

    // Can even work at compile time
    enum params = ([
        "--flag",
        "--num","100",
        "Jake",
        "--array","1","2","3",
        "--enum","foo",
        "--cb",
        "--cb1","cb-value",
        "--cb2","cb-v1","cb-v2",
        ].parseCLIArgs!Params).get;

    static assert(params.name      == "Jake");
    static assert(params.unused    == Params.init.unused);
    static assert(params.number    == 100);
    static assert(params.boolean   == true);
    static assert(params.enumValue == Params.Enum.foo);
    static assert(params.array     == [1,2,3]);
}