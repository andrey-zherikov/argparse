module argparse;


public import argparse.api.ansi;
public import argparse.api.argument;
public import argparse.api.argumentgroup;
public import argparse.api.cli;
public import argparse.api.command;
public import argparse.api.enums;
public import argparse.api.restriction;

public import argparse.config;
public import argparse.param;
public import argparse.result;


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

version(unittest)
{
    import argparse.internal.command : createCommand;
    import argparse.internal.commandinfo : getTopLevelCommandInfo;
    import argparse.internal.help : printHelp;
    import argparse.ansi : cleanStyleEnv, restoreStyleEnv;
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

unittest
{
    struct T
    {
        @NamedArgument
        int a;
        @(NamedArgument.Optional())
        int b;
        @(NamedArgument.Required())
        int c;
        @NamedArgument
        int d;
        @(NamedArgument.Required())
        int e;
        @NamedArgument
        int f;
    }

    enum config = {
        Config config;
        config.addHelp = false;
        return config;
    }();

    T receiver;
    auto a = createCommand!config(receiver, getTopLevelCommandInfo!T(config));
    assert(a.arguments.requiredGroup.argIndex == [2,4]);
    assert(a.arguments.argsNamed == ["a":0LU, "b":1LU, "c":2LU, "d":3LU, "e":4LU, "f":5LU]);
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
        config.addHelp = false;
        return config;
    }();

    T receiver;
    auto a = createCommand!config(receiver, getTopLevelCommandInfo!T(config));
    assert(a.arguments.requiredGroup.argIndex == []);
    assert(a.arguments.argsNamed == ["a":0LU, "b":1LU, "c":2LU, "d":3LU, "e":4LU, "f":5LU]);
    assert(a.arguments.argsPositional == []);
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
    struct T
    {
        @(NamedArgument("--"))
        int a;
    }
    static assert(!__traits(compiles, { enum p = CLI!T.parseArgs!((T t){})([]); }));
}

unittest
{

    import std.conv;
    import std.traits;

    struct params
    {
        int no_a;

        @(PositionalArgument(0, "a")
        .Description("Argument 'a'")
        .Validation!((int a) { return a > 3;})
        .PreValidation!((string s) { return s.length > 0;})
        .Validation!((int a) { return a > 0;})
        )
        int a;

        int no_b;

        @(NamedArgument(["b", "boo"]).Description("Flag boo")
        .AllowNoValue!55
        )
        int b;

        int no_c;
    }

    params receiver;
    auto a = createCommand!(Config.init)(receiver, getTopLevelCommandInfo!params(Config.init));
}

unittest
{
    struct T
    {
        string a;
        string b;
    }

    assert(CLI!T.parseArgs!((T t, string[] args) {
        assert(t == T("A"));
        assert(args == []);
        return 12345;
    })(["-a","A","--"]) == 12345);

    {
        T args;

        assert(CLI!T.parseArgs(args, [ "-a", "A"]));
        assert(CLI!T.parseArgs(args, [ "-b", "B"]));

        assert(args == T("A","B"));
    }
}

unittest
{
    struct T
    {
        string a;
    }

    import std.exception;

    assert(collectExceptionMsg(
        CLI!T.parseArgs!((T t, string[] args) {
            assert(t == T.init);
            assert(args.length == 0);
            throw new Exception("My Message.");
        })([]))
    == "My Message.");
    assert(collectExceptionMsg(
        CLI!T.parseArgs!((T t, string[] args) {
            assert(t == T("aa"));
            assert(args == ["-g"]);
            throw new Exception("My Message.");
        })(["-a","aa","-g"]))
    == "My Message.");
    assert(CLI!T.parseArgs!((T t, string[] args) {
        assert(t == T.init);
        assert(args.length == 0);
    })([]) == 0);
    assert(CLI!T.parseArgs!((T t, string[] args) {
        assert(t == T("aa"));
        assert(args == ["-g"]);
    })(["-a","aa","-g"]) == 0);
}

unittest
{
    struct T
    {
        string a;
        static auto color = ansiStylingArgument;
    }

    assert(CLI!T.parseArgs!((T t) { assert(false); })(["-g"]) != 0);
    assert(CLI!T.parseArgs!((T t) { assert(t == T.init); return 12345; })([]) == 12345);
    assert(CLI!T.parseArgs!((T t, string[] args) {
        assert(t == T.init);
        assert(args.length == 0);
        return 12345;
    })([]) == 12345);
    assert(CLI!T.parseArgs!((T t, string[] args) {
        assert(t == T("aa"));
        assert(args == ["-g"]);
        return 12345;
    })(["-a","aa","-g"]) == 12345);
    assert(CLI!T.parseArgs!((T t) {
        assert(t.color);
        return 12345;
    })(["--color"]) == 12345);
    assert(CLI!T.parseArgs!((T t) {
        assert(!t.color);
        return 12345;
    })(["--color","never"]) == 12345);
}

unittest
{
    void test(string[] args, alias expected)()
    {
        assert(CLI!(typeof(expected)).parseArgs!((t) {
            assert(t == expected);
            return 12345;
        })(args) == 12345);
    }

    struct T
    {
        @NamedArgument                           string x;
        @NamedArgument                           string foo;
        @(PositionalArgument(0, "a").Optional()) string a;
        @(PositionalArgument(1, "b").Optional()) string[] b;
    }
    test!(["--foo","FOO","-x","X"], T("X", "FOO"));
    test!(["--foo=FOO","-x=X"], T("X", "FOO"));
    test!(["--foo=FOO","1","-x=X"], T("X", "FOO", "1"));
    test!(["--foo=FOO","1","2","3","4"], T(string.init, "FOO", "1",["2","3","4"]));
    test!(["-xX"], T("X"));

    struct T1
    {
        @(PositionalArgument(0, "a")) string[3] a;
        @(PositionalArgument(1, "b")) string[] b;
    }
    test!(["1","2","3","4","5","6"], T1(["1","2","3"],["4","5","6"]));

    struct T2
    {
        bool foo = true;
    }
    test!(["--no-foo"], T2(false));

    struct T3
    {
        @(PositionalArgument(0, "a").Optional())
        string a = "not set";

        @(NamedArgument.Required())
        int b;
    }
    test!(["-b", "4"], T3("not set", 4));
}

unittest
{
    struct T
    {
        string x;
        string foo;
    }

    enum config = {
        Config config;
        config.caseSensitive = false;
        return config;
    }();

    assert(CLI!(config, T).parseArgs!((T t) { assert(t == T("X", "FOO")); return 12345; })(["--Foo","FOO","-X","X"]) == 12345);
    assert(CLI!(config, T).parseArgs!((T t) { assert(t == T("X", "FOO")); return 12345; })(["--FOo=FOO","-X=X"]) == 12345);
}

unittest
{
    struct T
    {
        bool a;
        bool b;
        string c;
    }
    enum config = {
        Config config;
        config.bundling = true;
        return config;
    }();

    assert(CLI!(config, T).parseArgs!((T t) { assert(t == T(true, true)); return 12345; })(["-a","-b"]) == 12345);
    assert(CLI!(config, T).parseArgs!((T t) { assert(t == T(true, true)); return 12345; })(["-ab"]) == 12345);
    assert(CLI!(config, T).parseArgs!((T t) { assert(t == T(true, true, "foo")); return 12345; })(["-abc=foo"]) == 12345);
}

unittest
{
    struct T
    {
        @NamedArgument("b","boo")
        bool b;
    }

    assert(CLI!T.parseArgs!((T t) { assert(t == T(true)); return 12345; })(["-b"]) == 12345);
    assert(CLI!T.parseArgs!((T t) { assert(t == T(true)); return 12345; })(["-b=true"]) == 12345);
    assert(CLI!T.parseArgs!((T t) { assert(t == T(false)); return 12345; })(["-b=false"]) == 12345);
    assert(CLI!T.parseArgs!((T t) { assert(t == T(false)); return 12345; })(["--no-b"]) == 12345);
    assert(CLI!T.parseArgs!((T t) { assert(false); })(["-b","true"]) == 1);
    assert(CLI!T.parseArgs!((T t) { assert(false); })(["-b","false"]) == 1);
    assert(CLI!T.parseArgs!((T t) { assert(t == T(true)); return 12345; })(["--boo"]) == 12345);
    assert(CLI!T.parseArgs!((T t) { assert(t == T(true)); return 12345; })(["--boo=true"]) == 12345);
    assert(CLI!T.parseArgs!((T t) { assert(t == T(false)); return 12345; })(["--boo=false"]) == 12345);
    assert(CLI!T.parseArgs!((T t) { assert(t == T(false)); return 12345; })(["--no-boo"]) == 12345);
    assert(CLI!T.parseArgs!((T t) { assert(false); })(["--boo","true"]) == 1);
    assert(CLI!T.parseArgs!((T t) { assert(false); })(["--boo","false"]) == 1);
}

unittest
{
    struct T
    {
        import std.sumtype: SumType;

        struct cmd1 { string a; }
        struct cmd2
        {
            string b;

            @TrailingArguments
            string[] args;
        }

        string c;
        string d;

        SumType!(cmd1, cmd2) cmd;
    }

    assert(CLI!T.parseArgs!((T t) { assert(t == T("C",null,typeof(T.cmd)(T.cmd2("B")))); return 12345; })(["-c","C","cmd2","-b","B"]) == 12345);
    assert(CLI!T.parseArgs!((T t) { assert(t == T("C",null,typeof(T.cmd)(T.cmd2("",["-b","B"])))); return 12345; })(["-c","C","cmd2","--","-b","B"]) == 12345);
}

unittest
{
    struct T
    {
        import std.sumtype: SumType;

        struct cmd1 {}
        struct cmd2 {}

        SumType!(cmd1, cmd2) cmd;
    }

    assert(CLI!T.parseArgs!((T t) { assert(t == T(typeof(T.cmd)(T.cmd1.init))); return 12345; })(["cmd1"]) == 12345);
    assert(CLI!T.parseArgs!((T t) { assert(t == T(typeof(T.cmd)(T.cmd2.init))); return 12345; })(["cmd2"]) == 12345);
}

unittest
{
    struct T
    {
        import std.sumtype: SumType;

        struct cmd1 { string a; }
        struct cmd2 { string b; }

        string c;
        string d;

        SumType!(cmd1, Default!cmd2) cmd;
    }

    assert(CLI!T.parseArgs!((T t) { assert(t == T("C",null,typeof(T.cmd)(Default!(T.cmd2)(T.cmd2("B"))))); return 12345; })(["-c","C","-b","B"]) == 12345);
    assert(CLI!T.parseArgs!((_) {assert(false);})(["-h"]) == 0);
    assert(CLI!T.parseArgs!((_) {assert(false);})(["--help"]) == 0);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

unittest
{
    struct T
    {
        import std.sumtype: SumType;

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

        @SubCommands
        SumType!(cmd1, cmd2) cmd;
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
        int a;
    }

    static assert(__traits(compiles, { mixin CLI!T.main!((params) => 0); }));
    static assert(__traits(compiles, { mixin CLI!T.main!((params, args) => 0); }));
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

    assert(CLI!T.parseArgs!((T t) { assert(t == T([1,2,3],[4,5])); return 12345; })(["-a","1","2","3","-b","4","5"]) == 12345);
    assert(CLI!T.parseArgs!((T t) { assert(t == T([1],[4,5])); return 12345; })(["-a","1","-b","4","5"]) == 12345);
}


unittest
{
    struct T
    {
        @(NamedArgument.Counter()) int a;
    }

    assert(CLI!T.parseArgs!((T t) { assert(t == T(3)); return 12345; })(["-a","-a","-a"]) == 12345);
}


unittest
{
    struct T
    {
        @(NamedArgument.AllowedValues!([1,3,5])) int a;
    }

    assert(CLI!T.parseArgs!((T t) { assert(t == T(3)); return 12345; })(["-a", "3"]) == 12345);
    assert(CLI!T.parseArgs!((T t) { assert(false); })(["-a", "2"]) != 0);    // "2" is not allowed
}

unittest
{
    struct T
    {
        @(PositionalArgument(0).AllowedValues!([1,3,5])) int a;
    }

    assert(CLI!T.parseArgs!((T t) { assert(t == T(3)); return 12345; })(["3"]) == 12345);
    assert(CLI!T.parseArgs!((T t) { assert(false); })(["2"]) != 0);    // "2" is not allowed
}

unittest
{
    struct T
    {
        @(NamedArgument.AllowedValues!(["apple","pear","banana"]))
        string fruit;
    }

    assert(CLI!T.parseArgs!((T t) { assert(t == T("apple")); return 12345; })(["--fruit", "apple"]) == 12345);
    assert(CLI!T.parseArgs!((T t) { assert(false); })(["--fruit", "kiwi"]) != 0);    // "kiwi" is not allowed
}

unittest
{
    enum Fruit { apple, pear, banana }
    struct T
    {
        Fruit fruit;
    }

    assert(CLI!T.parseArgs!((T t) { assert(t == T(Fruit.apple)); return 12345; })(["--fruit", "apple"]) == 12345);
    assert(CLI!T.parseArgs!((T t) { assert(false); })(["--fruit", "kiwi"]) != 0);    // "kiwi" is not allowed
}



unittest
{
    struct T
    {
        string a;
        string b;

        @TrailingArguments string[] args;
    }

    assert(CLI!T.parseArgs!((T t) { assert(t == T("A","",["-b","B"])); return 12345; })(["-a","A","--","-b","B"]) == 12345);
}

unittest
{
    struct T
    {
        @NamedArgument int i;
        @NamedArgument(["u","u1"])  uint u;
        @NamedArgument("d","d1")  double d;
    }

    assert(CLI!T.parseArgs!((T t) { assert(t == T(-5,8,12.345)); return 12345; })(["-i","-5","-u","8","-d","12.345"]) == 12345);
    assert(CLI!T.parseArgs!((T t) { assert(t == T(-5,8,12.345)); return 12345; })(["-i","-5","-u1","8","-d1","12.345"]) == 12345);
}

unittest
{
    struct T
    {
        int[]   a;
        int[][] b;
    }

    assert(CLI!T.parseArgs!((T t) { assert(t.a == [1,2,3,4,5]); return 12345; })(["-a","1","2","3","-a","4","5"]) == 12345);
    assert(CLI!T.parseArgs!((T t) { assert(t.b == [[1,2,3],[4,5]]); return 12345; })(["-b","1","2","3","-b","4","5"]) == 12345);
}

unittest
{
    struct T
    {
        int[] a;
    }

    enum cfg = {
        Config cfg;
        cfg.arraySep = ',';
        return cfg;
    }();

    assert(CLI!(cfg, T).parseArgs!((T t) { assert(t == T([1,2,3,4,5])); return 12345; })(["-a","1,2,3","-a","4","5"]) == 12345);
}

unittest
{
    struct T
    {
        int[string] a;
    }

    assert(CLI!T.parseArgs!((T t) { assert(t == T(["foo":3,"boo":7])); return 12345; })(["-a=foo=3","-a","boo=7"]) == 12345);
}

unittest
{
    struct T
    {
        int[string] a;
    }

    enum cfg = {
        Config cfg;
        cfg.arraySep = ',';
        return cfg;
    }();

    assert(CLI!(cfg, T).parseArgs!((T t) { assert(t == T(["foo":3,"boo":7])); return 12345; })(["-a=foo=3,boo=7"]) == 12345);
    assert(CLI!(cfg, T).parseArgs!((T t) { assert(t == T(["foo":3,"boo":7])); return 12345; })(["-a","foo=3,boo=7"]) == 12345);
}

unittest
{
    struct T
    {
        enum Fruit { apple, pear };

        Fruit a;
    }

    assert(CLI!T.parseArgs!((T t) { assert(t == T(T.Fruit.apple)); return 12345; })(["-a","apple"]) == 12345);
    assert(CLI!T.parseArgs!((T t) { assert(t == T(T.Fruit.pear)); return 12345; })(["-a=pear"]) == 12345);
}

unittest
{
    struct T
    {
        enum Fruit {
            apple,
            @ArgumentValue("no-apple","noapple")
            noapple
        };

        Fruit a;
    }

    assert(CLI!T.parseArgs!((T t) { assert(t == T(T.Fruit.apple)); return 12345; })(["-a","apple"]) == 12345);
    assert(CLI!T.parseArgs!((T t) { assert(t == T(T.Fruit.noapple)); return 12345; })(["-a=no-apple"]) == 12345);
    assert(CLI!T.parseArgs!((T t) { assert(t == T(T.Fruit.noapple)); return 12345; })(["-a","noapple"]) == 12345);
}

unittest
{
    struct T
    {
        string[] a;
    }

    assert(CLI!T.parseArgs!((T t) { assert(t == T(["1,2,3","4","5"])); return 12345; })(["-a","1,2,3","-a","4","5"]) == 12345);

    enum cfg = {
        Config cfg;
        cfg.arraySep = ',';
        return cfg;
    }();

    assert(CLI!(cfg, T).parseArgs!((T t) { assert(t == T(["1","2","3","4","5"])); return 12345; })(["-a","1,2,3","-a","4","5"]) == 12345);
}

unittest
{
    struct T
    {
        @(NamedArgument.AllowNoValue  !10) int a;
        @(NamedArgument.RequireNoValue!20) int b;
    }

    assert(CLI!T.parseArgs!((T t) { assert(t.a == 10); return 12345; })(["-a"]) == 12345);
    assert(CLI!T.parseArgs!((T t) { assert(t.b == 20); return 12345; })(["-b"]) == 12345);
    assert(CLI!T.parseArgs!((T t) { assert(t.a == 30); return 12345; })(["-a","30"]) == 12345);
    assert(CLI!T.parseArgs!((T t) { assert(false); })(["-b","30"]) != 0);
}

unittest
{
    struct T
    {
        @(NamedArgument
         .PreValidation!((string s) { return s.length > 1 && s[0] == '!'; })
         .Parse        !((string s) { return s[1]; })
         .Validation   !((char v) { return v >= '0' && v <= '9'; })
         .Action       !((ref int a, char v) { a = v - '0'; })
        )
        int a;
    }

    assert(CLI!T.parseArgs!((T t) { assert(t == T(4)); return 12345; })(["-a","!4"]) == 12345);
}

unittest
{
    static struct T
    {
        int a;

        @(NamedArgument("a")) void foo() { a++; }
    }

    assert(CLI!T.parseArgs!((T t) { assert(t == T(4)); return 12345; })(["-a","-a","-a","-a"]) == 12345);
}

unittest
{
    struct Value { string a; }
    struct T
    {
        @(NamedArgument.Parse!((string s) { return Value(s); }))
        Value s;
    }

    assert(CLI!T.parseArgs!((T t) { assert(t == T(Value("foo"))); return 12345; })(["-s","foo"]) == 12345);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

unittest
{
    @Command("MYPROG")
    struct T
    {
        @(NamedArgument.HideFromHelp())  string s;
    }

    assert(CLI!T.parseArgs!((T t) { assert(false); })(["-h","-s","asd"]) == 0);
    assert(CLI!T.parseArgs!((T t) { assert(false); })(["-h"]) == 0);

    assert(CLI!T.parseArgs!((T t, string[] args) { assert(false); })(["-h","-s","asd"]) == 0);
    assert(CLI!T.parseArgs!((T t, string[] args) { assert(false); })(["-h"]) == 0);
}

unittest
{
    @Command("MYPROG")
    struct T
    {
        @(NamedArgument.Required())  string s;
    }

    assert(CLI!T.parseArgs!((T t) { assert(false); })([]) != 0);
}

unittest
{
    @Command("MYPROG")
    struct T
    {
        @MutuallyExclusive()
        {
            string a;
            string b;
        }
    }

    // Either or no argument is allowed
    assert(CLI!T.parseArgs!((T t) {})(["-a","a"]) == 0);
    assert(CLI!T.parseArgs!((T t) {})(["-b","b"]) == 0);
    assert(CLI!T.parseArgs!((T t) {})([]) == 0);

    // Both arguments are not allowed
    assert(CLI!T.parseArgs!((T t) { assert(false); })(["-a","a","-b","b"]) != 0);
}

unittest
{
    @Command("MYPROG")
    struct T
    {
        @(MutuallyExclusive().Required())
        {
            string a;
            string b;
        }
    }

    // Either argument is allowed
    assert(CLI!T.parseArgs!((T t) {})(["-a","a"]) == 0);
    assert(CLI!T.parseArgs!((T t) {})(["-b","b"]) == 0);

    // Both arguments or no argument is not allowed
    assert(CLI!T.parseArgs!((T t) { assert(false); })([]) != 0);
    assert(CLI!T.parseArgs!((T t) { assert(false); })(["-a","a","-b","b"]) != 0);
}

unittest
{
    @Command("MYPROG")
    struct T
    {
        @RequiredTogether()
        {
            string a;
            string b;
        }
    }

    // Both or no argument is allowed
    assert(CLI!T.parseArgs!((T t) {})(["-a","a","-b","b"]) == 0);
    assert(CLI!T.parseArgs!((T t) {})([]) == 0);

    // Single argument is not allowed
    assert(CLI!T.parseArgs!((T t) { assert(false); })(["-a","a"]) != 0);
    assert(CLI!T.parseArgs!((T t) { assert(false); })(["-b","b"]) != 0);
}

unittest
{
    @Command("MYPROG")
    struct T
    {
        @(RequiredTogether().Required())
        {
            string a;
            string b;
        }
    }

    // Both arguments are allowed
    assert(CLI!T.parseArgs!((T t) {})(["-a","a","-b","b"]) == 0);

    // Single argument or no argument is not allowed
    assert(CLI!T.parseArgs!((T t) { assert(false); })(["-a","a"]) != 0);
    assert(CLI!T.parseArgs!((T t) { assert(false); })(["-b","b"]) != 0);
    assert(CLI!T.parseArgs!((T t) { assert(false); })([]) != 0);
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

        @(NamedArgument.HideFromHelp())  string hidden;

        enum Fruit { apple, pear };
        @(NamedArgument(["f","fruit"]).Required().Description("This is a help text for fruit. Very very very very very very very very very very very very very very very very very very very long text")) Fruit f;

        @(NamedArgument.AllowedValues!([1,4,16,8])) int i;

        @(PositionalArgument(0, "param0").Description("This is a help text for param0. Very very very very very very very very very very very very very very very very very very very long text")) string _param0;
        @(PositionalArgument(1).AllowedValues!(["q","a"])) string param1;

        @TrailingArguments string[] args;
    }

    import std.array: appender;

    auto a = appender!string;

    T receiver;
    auto cmd = createCommand!(Config.init)(receiver, getTopLevelCommandInfo!T(Config.init));

    auto isEnabled = ansiStylingArgument.isEnabled;
    scope(exit) ansiStylingArgument.isEnabled = isEnabled;
    ansiStylingArgument.isEnabled = false;

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
            @PositionalArgument(0) string p;
        }

        @(ArgumentGroup("group2").Description("group2 description"))
        @NamedArgument
        {
            string c;
            string d;
        }
        @PositionalArgument(1) string q;
    }

    import std.array: appender;

    auto a = appender!string;

    T receiver;
    auto cmd = createCommand!(Config.init)(receiver, getTopLevelCommandInfo!T(Config.init));

    auto isEnabled = ansiStylingArgument.isEnabled;
    scope(exit) ansiStylingArgument.isEnabled = isEnabled;
    ansiStylingArgument.isEnabled = false;

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
    import std.sumtype: SumType;

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

        SumType!(cmd1, CMD2) cmd;
    }

    import std.array: appender;

    auto a = appender!string;

    T receiver;
    auto cmd = createCommand!(Config.init)(receiver, getTopLevelCommandInfo!T(Config.init));

    auto isEnabled = ansiStylingArgument.isEnabled;
    scope(exit) ansiStylingArgument.isEnabled = isEnabled;
    ansiStylingArgument.isEnabled = false;

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
