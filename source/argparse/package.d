module argparse;


public import argparse.api.ansi;
public import argparse.api.argument;
public import argparse.api.argumentgroup;
public import argparse.api.cli;
public import argparse.api.command;
public import argparse.api.enums;
public import argparse.api.restriction;
public import argparse.api.subcommand;

public import argparse.config;
public import argparse.param;
public import argparse.result;


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

version(unittest)
{
    import argparse.internal.command : createCommand;
    import argparse.internal.commandinfo : getTopLevelCommandInfo;
    import argparse.internal.help : printHelp;
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

unittest
{
    struct T
    {
        @NamedArgument
        int a;
        @(NamedArgument.Optional)
        int b;
        @(NamedArgument.Required)
        int c;
        @NamedArgument
        int d;
        @(NamedArgument.Required)
        int e;
        @NamedArgument
        int f;
    }

    enum config = {
        Config config;
        config.addHelpArgument = false;
        return config;
    }();

    T receiver;
    auto a = createCommand!config(receiver, getTopLevelCommandInfo!T(config));
    assert(a.arguments.requiredGroup.argIndex == [2,4]);
    assert(a.arguments.argsNamedShort == ["a":0LU, "b":1LU, "c":2LU, "d":3LU, "e":4LU, "f":5LU]);
    assert(a.arguments.argsPositional == []);
}

unittest
{
    struct T
    {
        int a,b,c,d,e,f;
    }

    enum config = {
        Config config;
        config.addHelpArgument = false;
        return config;
    }();

    T receiver;
    auto a = createCommand!config(receiver, getTopLevelCommandInfo!T(config));
    assert(a.arguments.requiredGroup.argIndex == []);
    assert(a.arguments.argsNamedShort == ["a":0LU, "b":1LU, "c":2LU, "d":3LU, "e":4LU, "f":5LU]);
    assert(a.arguments.argsPositional == []);
}

unittest
{
    struct T
    {
        @PositionalArgument(0) int a;
        @PositionalArgument(1) int b;
    }
    T t;
    assert(CLI!T.parseArgs(t, ["1","2"]));
    assert(t == T(1,2));
}

unittest
{
    struct T
    {
        @PositionalArgument() int a;
        @PositionalArgument() int b;
    }
    T t;
    assert(CLI!T.parseArgs(t, ["1","2"]));
    assert(t == T(1,2));
}

unittest
{
    struct T
    {
        @PositionalArgument int a;
        @PositionalArgument int b;
    }
    T t;
    assert(CLI!T.parseArgs(t, ["1","2"]));
    assert(t == T(1,2));
}

unittest
{
    struct T1
    {
        @(NamedArgument("1"))
        @(NamedArgument("2"))
        int a;
    }
    static assert(!__traits(compiles, { T1 t; enum c = createCommand!(Config.init)(t, getTopLevelCommandInfo!T1(Config.init)); }));

    struct T2
    {
        @(NamedArgument("1"))
        int a;
        @(NamedArgument("1"))
        int b;
    }
    static assert(!__traits(compiles, { T2 t; enum c = createCommand!(Config.init)(t, getTopLevelCommandInfo!T2(Config.init)); }));

    struct T3
    {
        @(PositionalArgument(0)) int a;
        @(PositionalArgument(0)) int b;
    }
    static assert(!__traits(compiles, { T3 t; enum c = createCommand!(Config.init)(t, getTopLevelCommandInfo!T3(Config.init)); }));

    struct T4
    {
        @(PositionalArgument(0)) int a;
        @(PositionalArgument(2)) int b;
    }
    static assert(!__traits(compiles, { T4 t; enum c = createCommand!(Config.init)(t, getTopLevelCommandInfo!T4(Config.init)); }));

    struct T5
    {
        @(PositionalArgument(0)) int[] a;
        @(PositionalArgument(1)) int b;
    }
    static assert(!__traits(compiles, { T5 t; enum c = createCommand!(Config.init)(t, getTopLevelCommandInfo!T5(Config.init)); }));
}

unittest
{
    struct params
    {
        int no_a;

        @(PositionalArgument(0, "a")
        .Description("Argument 'a'")
        .PreValidation((string s) { return s.length > 0;})
        .Validation((int a) { return a > 0;})
        )
        int a;

        int no_b;

        @(NamedArgument(["b", "boo"]).Description("Flag boo")
        .AllowNoValue(55)
        )
        int b;

        int no_c;
    }

    params receiver;
    auto a = createCommand!(Config.init)(receiver, getTopLevelCommandInfo!params(Config.init));
}

unittest
{
    auto test(TYPE)(string[] args)
    {
        enum Config config = { variadicNamedArgument: true };

        TYPE t;
        assert(CLI!(config, TYPE).parseArgs(t, args));
        return t;
    }

    struct T
    {
        @NamedArgument                 string x;
        @NamedArgument                 string foo;
        @(PositionalArgument.Optional) string a;
        @(PositionalArgument.Optional) string[] b;
    }
    assert(test!T(["--foo", "FOO", "-x", "X"]) == T("X", "FOO"));
    assert(test!T(["--foo=FOO", "-x=X"]) == T("X", "FOO"));
    assert(test!T(["--foo=FOO", "1", "-x=X"]) == T("X", "FOO", "1"));
    assert(test!T(["--foo=FOO", "1", "2", "3", "4"]) == T(string.init, "FOO", "1", ["2", "3", "4"]));
    assert(test!T(["-xX"]) == T("X"));

    struct T1
    {
        @PositionalArgument string[3] a;
        @PositionalArgument string[] b;
    }
    assert(test!T1(["1", "2", "3", "4", "5", "6"]) == T1(["1", "2", "3"], ["4", "5", "6"]));

    struct T2
    {
        bool foo = true;
    }
    assert(test!T2(["--no-foo"]) == T2(false));

    struct T3
    {
        @(PositionalArgument.Optional)
        string a = "not set";

        @(NamedArgument.Required)
        int b;
    }
    assert(test!T3(["-b", "4"]) == T3("not set", 4));
}

unittest
{
    struct T
    {
        @NamedArgument("b","boo")
        bool b;
    }

    auto test(string[] args)
    {
        T t;
        assert(CLI!T.parseArgs(t, args));
        return t;
    }

    assert(test(["-b"]) == T(true));
    assert(test(["-b=true"]) == T(true));
    assert(test(["-b=false"]) == T(false));
    assert(test(["--no-b"]) == T(false));
    assert(test(["--boo"]) == T(true));
    assert(test(["--boo=true"]) == T(true));
    assert(test(["--boo=false"]) == T(false));
    assert(test(["--no-boo"]) == T(false));

    {
        T t;

        assert(CLI!T.parseArgs(t,["-b", "true"]).isError("Unrecognized arguments","true"));
        assert(CLI!T.parseArgs(t,["-b", "false"]).isError("Unrecognized arguments","false"));
        assert(CLI!T.parseArgs(t,["--boo","true"]).isError("Unrecognized arguments","true"));
        assert(CLI!T.parseArgs(t,["--boo","false"]).isError("Unrecognized arguments","false"));
    }
}

unittest
{
    struct T
    {
        struct cmd1 { string a; }
        struct cmd2
        {
            @NamedArgument
            string b;

            @(PositionalArgument.Optional)
            string[] args;
        }

        string c;
        string d;

        SubCommand!(cmd1, cmd2) cmd;
    }

    {
        T t;
        assert(CLI!T.parseArgs(t, ["-c","C","cmd2","-b","B"]));
        assert(t == T("C",null,typeof(T.cmd)(T.cmd2("B"))));
    }
    {
        T t;
        assert(CLI!T.parseArgs(t, ["-c","C","cmd2","--","-b","B"]));
        assert(t == T("C",null,typeof(T.cmd)(T.cmd2("",["-b","B"]))));
    }
}

unittest
{
    struct T
    {
        struct cmd1 {}
        struct cmd2 {}

        SubCommand!(cmd1, cmd2) cmd;
    }

    {
        T t;
        assert(CLI!T.parseArgs(t, ["cmd1"]));
        assert(t == T(typeof(T.cmd)(T.cmd1.init)));
    }
    {
        T t;
        assert(CLI!T.parseArgs(t, ["cmd2"]));
        assert(t == T(typeof(T.cmd)(T.cmd2.init)));
    }
}

unittest
{
    class T
    {
        static class cmd1 {string a;}
        static class cmd2 {string b;}

        SubCommand!(cmd1, cmd2) cmd;
    }

    {
        auto t = new T;
        assert(CLI!T.parseArgs(t, ["cmd1","-a","a"]));
        t.cmd.matchCmd!(
                (T.cmd1 _) => assert(_.a == "a"),
                (_) => assert(false)
        );
    }
    {
        auto t = new T;
        assert(CLI!T.parseArgs(t, ["cmd2","-b","b"]));
        t.cmd.matchCmd!(
                (T.cmd2 _) => assert(_.b == "b"),
                (_) => assert(false)
        );
    }
}

unittest
{
    struct T
    {
        struct cmd1 { string a; }
        struct cmd2 { string b; }

        string c;
        string d;

        SubCommand!(cmd1, Default!cmd2) cmd;
    }

    {
        T t;
        assert(CLI!T.parseArgs(t, ["-c","C","-b","B"]));
        assert(t == T("C",null,typeof(T.cmd)(T.cmd2("B"))));
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

unittest
{
    struct T
    {
        struct cmd1
        {
            string foo;
            string bar;
            string baz;
        }
        struct cmd2
        {
            string cat,can,dog;
        }

        @NamedArgument("apple","a")
        string a = "dummyA";
        @NamedArgument
        string s = "dummyS";
        @NamedArgument
        string b = "dummyB";

        @(NamedArgument.Hidden)
        string hidden;

        SubCommand!(cmd1, cmd2) cmd;
    }

    assert(CLI!T.completeArgs([]) == ["--apple","--help","-a","-b","-h","-s","cmd1","cmd2"]);
    assert(CLI!T.completeArgs([""]) == ["--apple","--help","-a","-b","-h","-s","cmd1","cmd2"]);
    assert(CLI!T.completeArgs(["-a"]) == ["-a"]);
    assert(CLI!T.completeArgs(["c"]) == ["cmd1","cmd2"]);
    assert(CLI!T.completeArgs(["cmd1"]) == ["cmd1"]);
    assert(CLI!T.completeArgs(["cmd1",""]) == ["--apple","--bar","--baz","--foo","--help","-a","-b","-h","-s","cmd1","cmd2"]);
    assert(CLI!T.completeArgs(["-a","val-a",""]) == ["--apple","--help","-a","-b","-h","-s","cmd1","cmd2"]);

    assert(!CLI!T.complete(["init","--bash","--commandName","mytool"]));
    assert(!CLI!T.complete(["init","--zsh"]));
    assert(!CLI!T.complete(["init","--tcsh"]));
    assert(!CLI!T.complete(["init","--fish"]));

    assert(CLI!T.complete(["init","--unknown"]));

    import std.process: environment;
    {
        environment["COMP_LINE"] = "mytool ";
        assert(!CLI!T.complete(["--bash","--","---","foo","foo"]));

        environment["COMP_LINE"] = "mytool c";
        assert(!CLI!T.complete(["--bash","--","c","---"]));

        environment.remove("COMP_LINE");
    }
    {
        environment["COMMAND_LINE"] = "mytool ";
        assert(!CLI!T.complete(["--tcsh","--"]));

        environment["COMMAND_LINE"] = "mytool c";
        assert(!CLI!T.complete(["--fish","--","c"]));

        environment.remove("COMMAND_LINE");
    }
}

unittest
{
    struct T
    {
        @(NamedArgument.NumberOfValues(1,3))
        int[] a;
        @(NamedArgument.NumberOfValues(2))
        int[] b;
    }

    auto test(string[] args)
    {
        enum Config config = { variadicNamedArgument: true };

        T t;
        assert(CLI!(config, T).parseArgs(t, args));
        return t;
    }


    assert(test(["-a","1","2","3","-b","4","5"]) == T([1,2,3],[4,5]));
    assert(test(["-a","1","-b","4","5"]) == T([1],[4,5]));
}

unittest
{
    struct T
    {
        @NamedArgument string[] a;
        @PositionalArgument string[]  b;
    }

    auto test(string[] args)
    {
        T t;
        assert(CLI!T.parseArgs(t, args));
        return t;
    }

    assert(test(["-a","a","b1","b2"]) == T(["a"],["b1","b2"]));
    assert(test(["-a","a","b1","b2", "-a", "a2"]) == T(["a","a2"],["b1","b2"]));
}


unittest
{
    struct T
    {
        @(NamedArgument.Counter) int a;
    }

    T t;
    assert(CLI!T.parseArgs(t, ["-a","-a","-a"]));
    assert(t == T(3));
}


unittest
{
    struct T
    {
        @(NamedArgument.AllowedValues(1,3,5)) int a;
    }

    T t;
    assert(CLI!T.parseArgs(t, ["-a", "3"]));
    assert(t == T(3));
    assert(CLI!T.parseArgs(t, ["-a", "2"]).isError("Invalid value","2"));
}

unittest
{
    struct T
    {
        @(PositionalArgument.AllowedValues(1,3,5)) int a;
    }

    T t;
    assert(CLI!T.parseArgs(t, ["3"]));
    assert(t == T(3));
    assert(CLI!T.parseArgs(t, ["2"]).isError("Invalid value","2"));
}

unittest
{
    struct T
    {
        @(NamedArgument.AllowedValues("apple","pear","banana"))
        string fruit;
    }

    T t;
    assert(CLI!T.parseArgs(t, ["--fruit", "apple"]));
    assert(t == T("apple"));
    assert(CLI!T.parseArgs(t, ["--fruit", "kiwi"]).isError("Invalid value","kiwi"));
}

unittest
{
    struct T
    {
        @NamedArgument
        string a;
        @NamedArgument
        string b;

        @PositionalArgument
        string[] args;
    }

    T t;
    assert(CLI!T.parseArgs(t, ["-a","A","--","-b","B"]));
    assert(t == T("A","",["-b","B"]));
}

unittest
{
    struct T
    {
        @NamedArgument int i;
        @NamedArgument(["u","u1"])  uint u;
        @NamedArgument("d","d1")  double d;
    }

    T t;
    assert(CLI!T.parseArgs(t, ["-i","-5","-u","8","-d","12.345"]));
    assert(t == T(-5,8,12.345));
    assert(CLI!T.parseArgs(t, ["-i","-5","--u1","8","--d1","12.345"]));
    assert(t == T(-5,8,12.345));
}

unittest
{
    struct T
    {
        enum Fruit {
            apple,
            @AllowedValues("no-apple","noapple")
            noapple
        };

        Fruit a;
    }

    T t;
    assert(CLI!T.parseArgs(t, ["-a","apple"]));
    assert(t == T(T.Fruit.apple));
    assert(CLI!T.parseArgs(t, ["-a=no-apple"]));
    assert(t == T(T.Fruit.noapple));
    assert(CLI!T.parseArgs(t, ["-a","noapple"]));
    assert(t == T(T.Fruit.noapple));
}

unittest
{
    struct T
    {
        @(NamedArgument.AllowNoValue(10)) int a;
        @(NamedArgument.ForceNoValue(20)) int b;
    }

    T t;
    assert(CLI!T.parseArgs(t, ["-a"]));
    assert(t.a == 10);
    assert(CLI!T.parseArgs(t, ["-b"]));
    assert(t.b == 20);
    assert(CLI!T.parseArgs(t, ["-a", "30"]));
    assert(t.a == 30);
    assert(CLI!T.parseArgs(t, ["-b","30"]).isError("Unrecognized arguments","30"));
}

unittest
{
    struct T
    {
        @(NamedArgument
         .PreValidation((string s) { return s.length > 1 && s[0] == '!'; })
         .Parse        ((string s) { return cast(char) s[1]; })
         .Validation   ((char v) { return v >= '0' && v <= '9'; })
         .Action       ((ref int a, char v) { a = v - '0'; })
        )
        int a;
    }

    T t;
    assert(CLI!T.parseArgs(t, ["-a","!4"]));
    assert(t == T(4));
}

unittest
{
    static struct T
    {
        int a;

        @(NamedArgument("a")) void foo() { a++; }
    }

    T t;
    assert(CLI!T.parseArgs(t, ["-a","-a","-a","-a"]));
    assert(t == T(4));
}

unittest
{
    struct Value { string a; }
    struct T
    {
        @(NamedArgument.Parse((string _) => Value(_)))
        Value s;
    }

    T t;
    assert(CLI!T.parseArgs(t, ["-s","foo"]));
    assert(t == T(Value("foo")));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

unittest
{
    struct T
    {
        @(NamedArgument.Required)  string s;
    }
    T t;
    assert(CLI!T.parseArgs(t, []).isError("The following argument is required","-s"));
}

unittest
{
    struct T
    {
        @MutuallyExclusive()
        {
            string a;
            string b;
        }
    }

    T t;

    // Either or no argument is allowed
    assert(CLI!T.parseArgs(t, ["-a","a"]));
    assert(CLI!T.parseArgs(t, ["-b","b"]));
    assert(CLI!T.parseArgs(t, []));

    // Both arguments are not allowed
    assert(CLI!T.parseArgs(t, ["-a","a","-b","b"]).isError("Argument","-a","is not allowed with argument","-b"));
}

unittest
{
    struct T
    {
        @(MutuallyExclusive.Required)
        {
            string a;
            string b;
        }
    }

    T t;

    // Either argument is allowed
    assert(CLI!T.parseArgs(t, ["-a","a"]));
    assert(CLI!T.parseArgs(t, ["-b","b"]));

    // Both arguments or no argument is not allowed
    assert(CLI!T.parseArgs(t, []).isError("One of the following arguments is required","-a","-b"));
    assert(CLI!T.parseArgs(t, ["-a","a","-b","b"]).isError("Argument","-a","is not allowed with argument","-b"));
}

unittest
{
    struct T
    {
        @RequiredTogether()
        {
            string a;
            string b;
        }
    }

    T t;

    // Both or no argument is allowed
    assert(CLI!T.parseArgs(t, ["-a","a","-b","b"]));
    assert(CLI!T.parseArgs(t, []));

    // Single argument is not allowed
    assert(CLI!T.parseArgs(t, ["-a","a"]).isError("Missed argument","-b","it is required by argument","-a"));
    assert(CLI!T.parseArgs(t, ["-b","b"]).isError("Missed argument","-a","it is required by argument","-b"));
}

unittest
{
    struct T
    {
        @(RequiredTogether.Required)
        {
            string a;
            string b;
        }
    }

    T t;

    // Both arguments are allowed
    assert(CLI!T.parseArgs(t, ["-a","a","-b","b"]));

    // Single argument or no argument is not allowed
    assert(CLI!T.parseArgs(t, ["-a","a"]).isError("Missed argument","-b","it is required by argument","-a"));
    assert(CLI!T.parseArgs(t, ["-b","b"]).isError("Missed argument","-a","it is required by argument","-b"));
    assert(CLI!T.parseArgs(t, []).isError("One of the following arguments is required","-a","-b"));
}


unittest
{
    struct SUB
    {
        @(NamedArgument.Required)
        string req_sub;
    }
    struct TOP
    {
        @(NamedArgument.Required)
        string req_top;

        SubCommand!SUB cmd;
    }

    auto test(string[] args)
    {
        TOP t;
        return CLI!TOP.parseArgs(t, args);
    }

    assert(test(["SUB"]).isError("The following argument is required","--req_top"));
    assert(test(["SUB","--req_sub","v"]).isError("The following argument is required","--req_top"));
    assert(test(["SUB","--req_top","v"]).isError("The following argument is required","--req_sub"));
    assert(test(["SUB","--req_sub","v","--req_top","v"]));
}


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

unittest
{
    static auto epilog() { return "custom epilog"; }
    @(Command("MYPROG")
     .Description("custom description")
     .Epilog(epilog)
    )
    struct T
    {
        @NamedArgument  string s;
        @(NamedArgument.Placeholder("VALUE"))  string p;

        @(NamedArgument.Hidden)  string hidden;

        enum Fruit { apple, pear };
        @(NamedArgument(["f","fruit"]).Required.Description("This is a help text for fruit. Very very very very very very very very very very very very very very very very very very very long text")) Fruit f;

        @(NamedArgument.AllowedValues(1,4,16,8)) int i;

        @(PositionalArgument(0, "param0").Description("This is a help text for param0. Very very very very very very very very very very very very very very very very very very very long text")) string _param0;
        @(PositionalArgument(1).AllowedValues("q","a")) string param1;
    }

    import std.array: appender;

    auto a = appender!string;

    T receiver;
    auto cmd = createCommand!(Config.init)(receiver, getTopLevelCommandInfo!T(Config.init));

    auto isEnabled = ansiStylingArgument.stdoutStyling;
    scope(exit) ansiStylingArgument.stdoutStyling = isEnabled;
    ansiStylingArgument.stdoutStyling = false;

    printHelp(_ => a.put(_), Config.init, cmd, [&cmd.arguments], "MYPROG");

    assert(a[]  == "Usage: MYPROG [-s S] [-p VALUE] -f {apple,pear} [-i {1,4,16,8}] [-h] param0 {q,a}\n\n"~
        "custom description\n\n"~
        "Required arguments:\n"~
        "  -f {apple,pear}, --fruit {apple,pear}\n"~
        "                   This is a help text for fruit. Very very very very very very\n"~
        "                   very very very very very very very very very very very very\n"~
        "                   very long text\n"~
        "  param0           This is a help text for param0. Very very very very very very\n"~
        "                   very very very very very very very very very very very very\n"~
        "                   very long text\n"~
        "  {q,a}\n\n"~
        "Optional arguments:\n"~
        "  -s S\n"~
        "  -p VALUE\n"~
        "  -i {1,4,16,8}\n"~
        "  -h, --help       Show this help message and exit\n\n"~
        "custom epilog\n");
}

unittest
{
    @(Command("MYPROG"))
    struct T
    {
        @(ArgumentGroup("group1").Description("group1 description"))
        {
            @NamedArgument
            {
                string a;
                string b;
            }
            @PositionalArgument string p;
        }

        @(ArgumentGroup("group2").Description("group2 description"))
        @NamedArgument
        {
            string c;
            string d;
        }
        @PositionalArgument string q;
    }

    import std.array: appender;

    auto a = appender!string;

    T receiver;
    auto cmd = createCommand!(Config.init)(receiver, getTopLevelCommandInfo!T(Config.init));

    auto isEnabled = ansiStylingArgument.stdoutStyling;
    scope(exit) ansiStylingArgument.stdoutStyling = isEnabled;
    ansiStylingArgument.stdoutStyling = false;

    printHelp(_ => a.put(_), Config.init, cmd, [&cmd.arguments], "MYPROG");


    assert(a[]  == "Usage: MYPROG [-a A] [-b B] [-c C] [-d D] [-h] p q\n\n"~
        "group1:\n"~
        "  group1 description\n\n"~
        "  -a A\n"~
        "  -b B\n"~
        "  p\n\n"~
        "group2:\n"~
        "  group2 description\n\n"~
        "  -c C\n"~
        "  -d D\n\n"~
        "Required arguments:\n"~
        "  q\n\n"~
        "Optional arguments:\n"~
        "  -h, --help    Show this help message and exit\n\n");
}

unittest
{
    @(Command("MYPROG"))
    struct T
    {
        @(Command.ShortDescription("Perform cmd 1"))
        struct cmd1
        {
            string a;
        }
        @(Command("very-long-command-name-2").ShortDescription("Perform cmd 2"))
        struct CMD2
        {
            string b;
        }

        string c;
        string d;

        SubCommand!(cmd1, CMD2) cmd;
    }

    import std.array: appender;

    auto a = appender!string;

    T receiver;
    auto cmd = createCommand!(Config.init)(receiver, getTopLevelCommandInfo!T(Config.init));

    auto isEnabled = ansiStylingArgument.stdoutStyling;
    scope(exit) ansiStylingArgument.stdoutStyling = isEnabled;
    ansiStylingArgument.stdoutStyling = false;

    printHelp(_ => a.put(_), Config.init, cmd, [&cmd.arguments], "MYPROG");

    assert(a[]  == "Usage: MYPROG [-c C] [-d D] [-h] <command> [<args>]\n\n"~
        "Available commands:\n"~
        "  cmd1          Perform cmd 1\n"~
        "  very-long-command-name-2\n"~
        "                Perform cmd 2\n\n"~
        "Optional arguments:\n"~
        "  -c C\n"~
        "  -d D\n"~
        "  -h, --help    Show this help message and exit\n\n");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// https://github.com/andrey-zherikov/argparse/issues/231
unittest {
    import std.process : environment;

    // Test an optional named argument
    @(Command("Program1"))
    struct Program1
    {
        @(NamedArgument(`user`).EnvFallback(`ARGPARSE_USERNAME`))
        string username;
    }

    Program1 p1;
    assert(CLI!Program1.parseArgs(p1, []));
    assert(p1.username is null);
    environment[`ARGPARSE_USERNAME`] = "John F. Doe";
    assert(CLI!Program1.parseArgs(p1, []));
    assert(p1.username == "John F. Doe");
    p1 = Program1.init;
    assert(CLI!Program1.parseArgs(p1, [`--user`, `Billy Joel`]));
    assert(p1.username == "Billy Joel");
    version (none) {
        // Uncomment after fixing:
        // https://github.com/andrey-zherikov/argparse/issues/219
        environment[`ARGPARSE_USERNAME`] = "";
        assert(CLI!Program1.parseArgs(p1, []));
        assert(p1.username !is null);
    }
    environment.remove(`ARGPARSE_USERNAME`);

    // Test a required Positional Argument
    @(Command("Program2"))
    struct Program2
    {
        @(PositionalArgument().EnvFallback(`ARGPARSE_REQUIRED_USERNAME`))
        string username;
    }
    Program2 p2;
    assert(!CLI!Program2.parseArgs(p2, []));
    assert(p2.username is null);
    environment[`ARGPARSE_REQUIRED_USERNAME`] = "RequiredUsername";
    assert(CLI!Program2.parseArgs(p2, []));
    assert(p2.username == "RequiredUsername");
    assert(CLI!Program2.parseArgs(p2, ["CLIUsername"]));
    assert(p2.username == "CLIUsername");
    environment.remove(`ARGPARSE_REQUIRED_USERNAME`);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// https://github.com/andrey-zherikov/argparse/issues/243
unittest
{
    import std.process : environment;
    struct Program {
        struct check {
        }

        struct serve {
            @(NamedArgument.EnvFallback("__NAME__"))
            string name = "default";

            @(NamedArgument.Required.EnvFallback("__PWD__"))
            string pwd;

            @(NamedArgument.Required)
            string url;
        }

        SubCommand!(check, Default!serve) cmd;
    }

    {
        Program p;
        assert(CLI!Program.parseArgs(p, [])       .isError("The following argument is required"));
        assert(CLI!Program.parseArgs(p, ["serve"]).isError("The following argument is required"));
    }
    {
        environment["__PWD__"] = "foo";
        scope(exit) environment.remove("__PWD__");

        Program p;
        assert(CLI!Program.parseArgs(p, [])       .isError("The following argument is required","url"));
        assert(CLI!Program.parseArgs(p, ["serve"]).isError("The following argument is required","url"));

        assert(CLI!Program.parseArgs(p, ["--url","url1"]));
        assert(p == Program(typeof(Program.cmd)(Program.serve(pwd: "foo", url:"url1"))));

        assert(CLI!Program.parseArgs(p, ["serve","--url","url2"]));
        assert(p == Program(typeof(Program.cmd)(Program.serve(pwd: "foo", url:"url2"))));
    }
}