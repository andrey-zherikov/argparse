module argparse;


import argparse.internal;

import std.typecons: Nullable;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

struct Config
{
    /**
       The assignment character used in options with parameters.
       Defaults to '='.
     */
    char assignChar = '=';

    /**
       When set to char.init, parameters to array and associative array receivers are
       treated as an individual argument. That is, only one argument is appended or
       inserted per appearance of the option switch. If `arraySep` is set to
       something else, then each parameter is first split by the separator, and the
       individual pieces are treated as arguments to the same option.

       Defaults to char.init
     */
    char arraySep = char.init;

    /**
       The option character.
       Defaults to '-'.
     */
    char namedArgChar = '-';

    /**
       The string that conventionally marks the end of all options.
       Assigning an empty string to `endOfArgs` effectively disables it.
       Defaults to "--".
     */
    string endOfArgs = "--";

    /**
       If set then argument names are case-sensitive.
       Defaults to true.
     */
    bool caseSensitive = true;

    /**
        Single-letter arguments can be bundled together, i.e. "-abc" is the same as "-a -b -c".
        Disabled by default.
     */
    bool bundling = false;

    /**
       Add a -h/--help option to the parser.
       Defaults to true.
     */
    bool addHelp = true;

    /**
       Delegate that processes error messages if they happen during argument parsing.
       By default all errors are printed to stderr.
     */
    package void delegate(string s) nothrow errorHandlerFunc;

    @property auto errorHandler(void function(string s) nothrow func)
    {
        return errorHandlerFunc = (string msg) { func(msg); };
    }

    @property auto errorHandler(void delegate(string s) nothrow func)
    {
        return errorHandlerFunc = func;
    }


    package void onError(A...)(A args) const nothrow
    {
        import std.conv: text;
        import std.stdio: stderr, writeln;

        try
        {
            if(errorHandlerFunc)
                errorHandlerFunc(text!A(args));
            else
                stderr.writeln("Error: ", args);
        }
        catch(Exception e)
        {
            throw new Error(e.msg);
        }
    }
}

unittest
{
    Config.init.onError("--just testing error func--",1,2.3,false);
    Config c;
    c.errorHandler = (string s){};
    c.onError("--just testing error func--",1,2.3,false);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

struct Param(VALUE_TYPE)
{
    const Config config;
    string name;

    static if(!is(VALUE_TYPE == void))
        VALUE_TYPE value;
}

alias RawParam = Param!(string[]);

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

struct Result
{
    int  resultCode;

    package enum Status { failure, success, unknownArgument };
    package Status status;

    package string errorMsg;

    package const(string)[] suggestions;

    package static enum Failure = Result(1, Status.failure);
    package static enum Success = Result(0, Status.success);
    package static enum UnknownArgument = Result(0, Status.unknownArgument);

    bool opCast(type)() const if (is(type == bool))
    {
        return status == Status.success;
    }

    package static auto Error(A...)(A args) nothrow
    {
        import std.conv: text;
        import std.stdio: stderr, writeln;

        return Result(1, Status.failure, text!A(args));
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package struct ArgumentInfo
{
    package:

    string[] names;

    string description;
    string placeholder;

    void setAllowedValues(alias names)()
    {
        if(placeholder.length == 0)
        {
            import std.conv: to;
            import std.array: join;
            import std.format: format;
            placeholder = "{%s}".format(names.to!(string[]).join(','));
        }
    }

    bool hideFromHelp = false;      // if true then this argument is not printed on help page

    bool required;

    Nullable!uint position;

    @property bool positional() const { return !position.isNull; }

    Nullable!ulong minValuesCount;
    Nullable!ulong maxValuesCount;

    auto checkValuesCount(string argName, ulong count) const
    {
        immutable min = minValuesCount.get;
        immutable max = maxValuesCount.get;

        // override for boolean flags
        if(allowBooleanNegation && count == 1)
            return Result.Success;

        if(min == max && count != min)
        {
            return Result.Error("argument ",argName,": expected ",min,min == 1 ? " value" : " values");
        }
        if(count < min)
        {
            return Result.Error("argument ",argName,": expected at least ",min,min == 1 ? " value" : " values");
        }
        if(count > max)
        {
            return Result.Error("argument ",argName,": expected at most ",max,max == 1 ? " value" : " values");
        }

        return Result.Success;
    }

    bool allowBooleanNegation = true;
    bool ignoreInDefaultCommand;
}


unittest
{
    ArgumentInfo info;
    info.allowBooleanNegation = false;
    info.minValuesCount = 2;
    info.maxValuesCount = 4;

    alias isError = (Result res) => !res && res.errorMsg.length > 0;

    assert( isError(info.checkValuesCount("", 1)));
    assert(!isError(info.checkValuesCount("", 2)));
    assert(!isError(info.checkValuesCount("", 3)));
    assert(!isError(info.checkValuesCount("", 4)));
    assert( isError(info.checkValuesCount("", 5)));
}

unittest
{
    ArgumentInfo info;
    info.allowBooleanNegation = false;
    info.minValuesCount = 2;
    info.maxValuesCount = 2;

    alias isError = (Result res) => !res && res.errorMsg.length > 0;

    assert( isError(info.checkValuesCount("", 1)));
    assert(!isError(info.checkValuesCount("", 2)));
    assert( isError(info.checkValuesCount("", 3)));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package struct ArgumentUDA(alias ValueParseFunctions)
{
    package ArgumentInfo info;

    package alias parsingFunc = ValueParseFunctions;

    public auto ref Description(string text)
    {
        info.description = text;
        return this;
    }

    public auto ref HideFromHelp(bool hide = true)
    {
        info.hideFromHelp = hide;
        return this;
    }

    public auto ref Placeholder(string value)
    {
        info.placeholder = value;
        return this;
    }

    public auto ref Required()
    {
        info.required = true;
        return this;
    }

    public auto ref Optional()
    {
        info.required = false;
        return this;
    }

    public auto ref NumberOfValues(ulong num)
    {
        info.minValuesCount = num;
        info.maxValuesCount = num;
        return this;
    }

    public auto ref NumberOfValues(ulong min, ulong max)
    {
        info.minValuesCount = min;
        info.maxValuesCount = max;
        return this;
    }

    public auto ref MinNumberOfValues(ulong min)
    {
        assert(min <= info.maxValuesCount.get(ulong.max));

        info.minValuesCount = min;
        return this;
    }

    public auto ref MaxNumberOfValues(ulong max)
    {
        assert(max >= info.minValuesCount.get(0));

        info.maxValuesCount = max;
        return this;
    }
}

package enum bool isArgumentUDA(T) = (is(typeof(T.info) == ArgumentInfo) && is(T.parsingFunc));

unittest
{
    ArgumentUDA!void arg;
    assert(!arg.info.hideFromHelp);
    assert(!arg.info.required);
    assert(arg.info.minValuesCount.isNull);
    assert(arg.info.maxValuesCount.isNull);

    arg = arg.Description("desc").Placeholder("text");
    assert(arg.info.description == "desc");
    assert(arg.info.placeholder == "text");

    arg = arg.HideFromHelp().Required().NumberOfValues(10);
    assert(arg.info.hideFromHelp);
    assert(arg.info.required);
    assert(arg.info.minValuesCount.get == 10);
    assert(arg.info.maxValuesCount.get == 10);

    arg = arg.Optional().NumberOfValues(20,30);
    assert(!arg.info.required);
    assert(arg.info.minValuesCount.get == 20);
    assert(arg.info.maxValuesCount.get == 30);

    arg = arg.MinNumberOfValues(2).MaxNumberOfValues(3);
    assert(arg.info.minValuesCount.get == 2);
    assert(arg.info.maxValuesCount.get == 3);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

auto PositionalArgument(uint pos)
{
    auto arg = ArgumentUDA!(ValueParseFunctions!(void, void, void, void, void, void))(ArgumentInfo()).Required();
    arg.info.position = pos;
    return arg;
}

auto PositionalArgument(uint pos, string name)
{
    auto arg = ArgumentUDA!(ValueParseFunctions!(void, void, void, void, void, void))(ArgumentInfo([name])).Required();
    arg.info.position = pos;
    return arg;
}

auto NamedArgument(string[] name...)
{
    return ArgumentUDA!(ValueParseFunctions!(void, void, void, void, void, void))(ArgumentInfo(name)).Optional();
}

auto NamedArgument(string name)
{
    return ArgumentUDA!(ValueParseFunctions!(void, void, void, void, void, void))(ArgumentInfo([name])).Optional();
}

struct TrailingArguments {}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package struct Group
{
    package string name;
    package string description;
    package size_t[] arguments;

    public auto ref Description(string text)
    {
        description = text;
        return this;
    }

}

auto ArgumentGroup(string name)
{
    return Group(name);
}

unittest
{
    auto g = ArgumentGroup("name").Description("description");
    assert(g.name == "name");
    assert(g.description == "description");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package struct RestrictionGroup
{
    package string location;

    package enum Type { together, exclusive }
    package Type type;

    package size_t[] arguments;

    package bool required;

    public auto ref Required()
    {
        required = true;
        return this;
    }
}

auto RequiredTogether(string file=__FILE__, uint line = __LINE__)()
{
    import std.conv: to;
    return RestrictionGroup(file~":"~line.to!string, RestrictionGroup.Type.together);
}

auto MutuallyExclusive(string file=__FILE__, uint line = __LINE__)()
{
    import std.conv: to;
    return RestrictionGroup(file~":"~line.to!string, RestrictionGroup.Type.exclusive);
}

unittest
{
    auto t = RequiredTogether();
    assert(t.location.length > 0);
    assert(t.type == RestrictionGroup.Type.together);

    auto e = MutuallyExclusive();
    assert(e.location.length > 0);
    assert(e.type == RestrictionGroup.Type.exclusive);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

struct SubCommands {}

// Default subcommand
struct Default(COMMAND)
{
    COMMAND command;
    alias command this;
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package struct CommandInfo
{
    package string[] names = [""];
    package string usage;
    package string description;
    package string shortDescription;
    package string epilog;

    public auto ref Usage(string text)
    {
        usage = text;
        return this;
    }

    public auto ref Description(string text)
    {
        description = text;
        return this;
    }

    public auto ref ShortDescription(string text)
    {
        shortDescription = text;
        return this;
    }

    public auto ref Epilog(string text)
    {
        epilog = text;
        return this;
    }
}

unittest
{
    CommandInfo c;
    c = c.Usage("usg").Description("desc").ShortDescription("sum").Epilog("epi");
    assert(c.names == [""]);
    assert(c.usage == "usg");
    assert(c.description == "desc");
    assert(c.shortDescription == "sum");
    assert(c.epilog == "epi");
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

    static assert(CommandArguments!T(config).arguments.arguments.length == 6);

    auto a = CommandArguments!T(config);
    assert(a.arguments.requiredGroup.arguments == [2,4]);
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

    static assert(CommandArguments!T(config).arguments.arguments.length == 6);

    auto a = CommandArguments!T(config);
    assert(a.arguments.requiredGroup.arguments == []);
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
    static assert(!__traits(compiles, { CommandArguments!T1(Config.init); }));

    struct T2
    {
        @(NamedArgument("1"))
        int a;
        @(NamedArgument("1"))
        int b;
    }
    static assert(!__traits(compiles, { CommandArguments!T1(Config.init); }));

    struct T3
    {
        @(PositionalArgument(0)) int a;
        @(PositionalArgument(0)) int b;
    }
    static assert(!__traits(compiles, { CommandArguments!T3(Config.init); }));

    struct T4
    {
        @(PositionalArgument(0)) int a;
        @(PositionalArgument(2)) int b;
    }
    static assert(!__traits(compiles, { CommandArguments!T4(Config.init); }));
}

unittest
{
    import std.exception;

    struct T
    {
        @(NamedArgument("--"))
        int a;
    }
    static assert(!__traits(compiles, { enum p = CLI!T.parseArgs!((T t){})([]); }));
    assertThrown(CLI!T.parseArgs!((T t){})([]));
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

    enum p = CommandArguments!params(Config.init);
    static assert(p.findNamedArgument("a").arg is null);
    static assert(p.findNamedArgument("b").arg !is null);
    static assert(p.findNamedArgument("boo").arg !is null);
    static assert(p.findPositionalArgument(0).arg !is null);
    static assert(p.findPositionalArgument(1).arg is null);
    static assert(p.getParseFunction!false(p.findNamedArgument("b").index) !is null);
    static assert(p.getParseFunction!true(p.findNamedArgument("b").index) !is null);
}

unittest
{
    import std.typecons : tuple;

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
    static assert(CLI!T.parseArgs!((T t, string[] args) {
        assert(t == T.init);
        assert(args.length == 0);
        return 12345;
    })([]) == 12345);
    static assert(CLI!T.parseArgs!((T t, string[] args) {
        assert(t == T("aa"));
        assert(args == ["-g"]);
        return 12345;
    })(["-a","aa","-g"]) == 12345);
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
    }
    enum config = {
        Config config;
        config.bundling = true;
        return config;
    }();

    assert(CLI!(config, T).parseArgs!((T t) { assert(t == T(true, true)); return 12345; })(["-a","-b"]) == 12345);
    assert(CLI!(config, T).parseArgs!((T t) { assert(t == T(true, true)); return 12345; })(["-ab"]) == 12345);
}

unittest
{
    struct T
    {
        bool b;
    }

    assert(CLI!T.parseArgs!((T t) { assert(t == T(true)); return 12345; })(["-b"]) == 12345);
    assert(CLI!T.parseArgs!((T t) { assert(t == T(true)); return 12345; })(["-b=true"]) == 12345);
    assert(CLI!T.parseArgs!((T t) { assert(t == T(false)); return 12345; })(["-b=false"]) == 12345);
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

template CLI(Config config, COMMANDS...)
{
    mixin template main(alias newMain)
    {
        import std.sumtype: SumType, match;

        private struct Program
        {
            SumType!COMMANDS cmd;   // Sub-commands
        }

        private auto forwardMain(Args...)(Program prog, auto ref Args args)
        {
            import core.lifetime: forward;
            return prog.cmd.match!(_ => newMain(_, forward!args));
        }

        mixin CLI!(config, Program).main!forwardMain;
    }
}

template CLI(Config config, COMMAND)
{
    static Result parseKnownArgs(ref COMMAND receiver, string[] args, out string[] unrecognizedArgs)
    {
        auto parser = Parser(config, args);

        auto command = CommandArguments!COMMAND(config);
        auto res = parser.parseAll!false(command, receiver);
        if(!res)
            return res;

        unrecognizedArgs = parser.unrecognizedArgs;

        return Result.Success;
    }

    static Result parseKnownArgs(ref COMMAND receiver, ref string[] args)
    {
        string[] unrecognizedArgs;

        auto res = parseKnownArgs(receiver, args, unrecognizedArgs);
        if(res)
            args = unrecognizedArgs;

        return res;
    }

    static Result parseArgs(ref COMMAND receiver, string[] args)
    {
        auto res = parseKnownArgs(receiver, args);
        if(res && args.length > 0)
        {
            config.onError("Unrecognized arguments: ", args);
            return Result.Failure;
        }

        return res;
    }

    static int parseArgs(alias newMain)(string[] args, COMMAND initialValue = COMMAND.init)
        if(__traits(compiles, { newMain(COMMAND.init); }))
    {
        alias value = initialValue;

        auto res = parseArgs(value, args);
        if(!res)
            return res.resultCode;

        static if(__traits(compiles, { int a = cast(int) newMain(value); }))
            return cast(int) newMain(value);
        else
        {
            newMain(value);
            return 0;
        }
    }

    static int parseArgs(alias newMain)(string[] args, COMMAND initialValue = COMMAND.init)
        if(__traits(compiles, { newMain(COMMAND.init, string[].init); }))
    {
        alias value = initialValue;

        auto res = parseKnownArgs(value, args);
        if(!res)
            return res.resultCode;

        static if(__traits(compiles, { int a = cast(int) newMain(value, args); }))
            return cast(int) newMain(value, args);
        else
        {
            newMain(value, args);
            return 0;
        }
    }

    string[] completeArgs(string[] args)
    {
        import std.algorithm: sort, uniq;
        import std.array: array;

        auto command = CommandArguments!COMMAND(config);

        auto parser = Parser(config, args.length == 0 ? [""] : args);

        COMMAND dummy;

        auto res = parser.parseAll!true(command, dummy);

        return res ? res.suggestions.dup.sort.uniq.array : [];
    }

    int complete(string[] args)
    {
        import argparse.completer;
        import std.sumtype: match;

        // dmd fails with core.exception.OutOfMemoryError@core\lifetime.d(137): Memory allocation failed
        // if we call anything from CLI!(config, Complete!COMMAND) so we have to directly call parser here

        Complete!COMMAND receiver;

        auto parser = Parser(config, args);

        auto command = CommandArguments!(Complete!COMMAND)(config);
        auto res = parser.parseAll!false(command, receiver);
        if(!res)
            return 1;

        if(res && parser.unrecognizedArgs.length > 0)
        {
            config.onError("Unrecognized arguments: ", parser.unrecognizedArgs);
            return 1;
        }

        receiver.cmd.match!(_ => _.execute!config());

        return 0;
    }

    mixin template mainComplete()
    {
        int main(string[] argv)
        {
            return CLI!(config, COMMAND).complete(argv[1..$]);
        }
    }

    mixin template main(alias newMain)
    {
        version(argparse_completion)
        {
            mixin CLI!(config, COMMAND).mainComplete;
        }
        else
        {
            int main(string[] argv)
            {
                return CLI!(config, COMMAND).parseArgs!(newMain)(argv[1..$]);
            }
        }
    }
}

alias CLI(COMMANDS...) = CLI!(Config.init, COMMANDS);


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








////////////////////////////////////////////////////////////////////////////////////////////////////
// User defined attributes
////////////////////////////////////////////////////////////////////////////////////////////////////

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


auto PreValidation(alias func, ARG)(ARG arg)
if(isArgumentUDA!ARG)
{
    return ArgumentUDA!(arg.parsingFunc.changePreValidation!func)(arg.tupleof);
}

auto Parse(alias func, ARG)(ARG arg)
if(isArgumentUDA!ARG)
{
    return ArgumentUDA!(arg.parsingFunc.changeParse!func)(arg.tupleof);
}

auto Validation(alias func, ARG)(ARG arg)
if(isArgumentUDA!ARG)
{
    return ArgumentUDA!(arg.parsingFunc.changeValidation!func)(arg.tupleof);
}

auto Action(alias func, ARG)(ARG arg)
if(isArgumentUDA!ARG)
{
    return ArgumentUDA!(arg.parsingFunc.changeAction!func)(arg.tupleof);
}

auto AllowNoValue(alias valueToUse, ARG)(ARG arg)
if(isArgumentUDA!ARG)
{
    auto desc = ArgumentUDA!(arg.parsingFunc.changeNoValueAction!(() { return valueToUse; }))(arg.tupleof);
    desc.info.minValuesCount = 0;
    return desc;
}

auto RequireNoValue(alias valueToUse, ARG)(ARG arg)
if(isArgumentUDA!ARG)
{
    auto desc = arg.AllowNoValue!valueToUse;
    desc.info.minValuesCount = 0;
    desc.info.maxValuesCount = 0;
    return desc;
}

auto Counter(ARG)(ARG arg)
if(isArgumentUDA!ARG)
{
    struct CounterParsingFunction
    {
        static bool parse(T)(ref T receiver, const ref RawParam param)
        {
            assert(param.value.length == 0);

            ++receiver;

            return true;
        }
    }

    auto desc = ArgumentUDA!(CounterParsingFunction)(arg.tupleof);
    desc.info.minValuesCount = 0;
    desc.info.maxValuesCount = 0;
    return desc;
}


unittest
{
    struct T
    {
        @(NamedArgument.Counter()) int a;
    }

    assert(CLI!T.parseArgs!((T t) { assert(t == T(3)); return 12345; })(["-a","-a","-a"]) == 12345);
}


auto AllowedValues(alias values, ARG)(ARG arg)
{
    import std.array : assocArray;
    import std.range : repeat;
    import std.traits: KeyType;

    enum valuesAA = assocArray(values, false.repeat);

    auto desc = arg.Validation!(Validators.ValueInList!(values, KeyType!(typeof(valuesAA))));
    desc.info.setAllowedValues!values;
    return desc;
}


unittest
{
    struct T
    {
        @(NamedArgument.AllowedValues!([1,3,5])) int a;
    }

    assert(CLI!T.parseArgs!((T t) { assert(t == T(3)); return 12345; })(["-a", "3"]) == 12345);
    assert(CLI!T.parseArgs!((T t) { assert(false); })(["-a", "2"]) != 0);    // "kiwi" is not allowed
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
        @NamedArgument
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
        @NamedArgument int[]   a;
        @NamedArgument int[][] b;
    }

    assert(CLI!T.parseArgs!((T t) { assert(t.a == [1,2,3,4,5]); return 12345; })(["-a","1","2","3","-a","4","5"]) == 12345);
    assert(CLI!T.parseArgs!((T t) { assert(t.b == [[1,2,3],[4,5]]); return 12345; })(["-b","1","2","3","-b","4","5"]) == 12345);
}

unittest
{
    struct T
    {
        @NamedArgument int[] a;
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
        @NamedArgument int[string] a;
    }

    assert(CLI!T.parseArgs!((T t) { assert(t == T(["foo":3,"boo":7])); return 12345; })(["-a=foo=3","-a","boo=7"]) == 12345);
}

unittest
{
    struct T
    {
        @NamedArgument int[string] a;
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

        @NamedArgument Fruit a;
    }

    assert(CLI!T.parseArgs!((T t) { assert(t == T(T.Fruit.apple)); return 12345; })(["-a","apple"]) == 12345);
    assert(CLI!T.parseArgs!((T t) { assert(t == T(T.Fruit.pear)); return 12345; })(["-a=pear"]) == 12345);
}

unittest
{
    struct T
    {
        @NamedArgument string[] a;
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


auto Command(string[] name...)
{
    return CommandInfo(name.dup);
}

unittest
{
    auto a = Command("MYPROG");
    assert(a.names == ["MYPROG"]);
}


////////////////////////////////////////////////////////////////////////////////////////////////////
/// Help-printing functions
////////////////////////////////////////////////////////////////////////////////////////////////////


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


