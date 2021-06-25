// THIS CONTENT SHOULD BE IN SYNC WITH README

unittest
{
    import argparse;

    struct Params
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
        enum Enum { unset, foo, boo };
        @NamedArgument("enum")
        Enum enumValue;

        // Use array to store multiple values
        @NamedArgument("array")
        int[] array;
    }

    // Can even work at compile time
    enum params = (["--flag","--num","100","Jake","--array","1","2","3","--enum","foo"].parseCLIArgs!Params).get;

    static assert(params.name      == "Jake");
    static assert(params.unused    == Params.init.unused);
    static assert(params.number    == 100);
    static assert(params.boolean   == true);
    static assert(params.enumValue == Params.Enum.foo);
    static assert(params.array     == [1,2,3]);
}