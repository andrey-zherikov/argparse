module argparse;


import argparse.internal;
import argparse.parser: callParser;
import argparse.help: Style;
import argparse.ansi;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/// Public API
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
       Styling and coloring mode.
       Defaults to auto-detectection of the capability.
     */
    enum StylingMode { autodetect, on, off }
    StylingMode stylingMode = StylingMode.autodetect;

    package void delegate(StylingMode)[] setStylingModeHandlers;
    package void setStylingMode(StylingMode mode) const
    {
        foreach(dg; setStylingModeHandlers)
            dg(mode);
    }

    /**
       Help style.
     */
    Style helpStyle = Style.Default;

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
    const Config* config;
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

    package static auto Error(A...)(A args)
    {
        import std.conv: text;
        import std.stdio: stderr, writeln;

        return Result(1, Status.failure, text!A(args));
    }

    version(unittest)
    {
        package bool isError(string text)
        {
            import std.algorithm: canFind;
            return (!cast(bool) this) && errorMsg.canFind(text);
        }
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package struct ArgumentInfo
{
    import std.typecons: Nullable;

    package:

    string[] names;

    LazyString description;
    string placeholder;

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

package string formatAllowedValues(alias names)()
{
    import std.conv: to;
    import std.array: join;
    import std.format: format;
    return "{%s}".format(names.to!(string[]).join(','));
}


unittest
{
    auto info(int min, int max)
    {
        ArgumentInfo info;
        info.allowBooleanNegation = false;
        info.minValuesCount = min;
        info.maxValuesCount = max;
        return info;
    }

    assert(info(2,4).checkValuesCount("", 1).isError("expected at least 2 values"));
    assert(info(2,4).checkValuesCount("", 2));
    assert(info(2,4).checkValuesCount("", 3));
    assert(info(2,4).checkValuesCount("", 4));
    assert(info(2,4).checkValuesCount("", 5).isError("expected at most 4 values"));

    assert(info(2,2).checkValuesCount("", 1).isError("expected 2 values"));
    assert(info(2,2).checkValuesCount("", 2));
    assert(info(2,2).checkValuesCount("", 3).isError("expected 2 values"));

    assert(info(1,1).checkValuesCount("", 0).isError("expected 1 value"));
    assert(info(1,1).checkValuesCount("", 1));
    assert(info(1,1).checkValuesCount("", 2).isError("expected 1 value"));

    assert(info(0,1).checkValuesCount("", 0));
    assert(info(0,1).checkValuesCount("", 1));
    assert(info(0,1).checkValuesCount("", 2).isError("expected at most 1 value"));

    assert(info(1,2).checkValuesCount("", 0).isError("expected at least 1 value"));
    assert(info(1,2).checkValuesCount("", 1));
    assert(info(1,2).checkValuesCount("", 2));
    assert(info(1,2).checkValuesCount("", 3).isError("expected at most 2 values"));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package struct ArgumentUDA(ValueParseFunctions)
{
    package ArgumentInfo info;

    package alias parsingFunc = ValueParseFunctions;

    package auto addDefaults(T)(ArgumentUDA!T uda)
    {
        import std.traits: getUDAs;

        auto newInfo = info;

        if(newInfo.names.length == 0) newInfo.names = uda.info.names;
        if(newInfo.placeholder.length == 0) newInfo.placeholder = uda.info.placeholder;
        if(!newInfo.description.isSet()) newInfo.description = uda.info.description;
        if(newInfo.position.isNull()) newInfo.position = uda.info.position;
        if(newInfo.minValuesCount.isNull()) newInfo.minValuesCount = uda.info.minValuesCount;
        if(newInfo.maxValuesCount.isNull()) newInfo.maxValuesCount = uda.info.maxValuesCount;

        return ArgumentUDA!(parsingFunc.addDefaults!(uda.parsingFunc))(newInfo);
    }
}

private enum bool isArgumentUDA(T) = (is(typeof(T.info) == ArgumentInfo) && is(T.parsingFunc));

public auto ref Description(T)(auto ref ArgumentUDA!T uda, string text)
{
    uda.info.description = text;
    return uda;
}

public auto ref Description(T)(auto ref ArgumentUDA!T uda, string delegate() text)
{
    uda.info.description = text;
    return uda;
}

public auto ref HideFromHelp(T)(auto ref ArgumentUDA!T uda, bool hide = true)
{
    uda.info.hideFromHelp = hide;
    return uda;
}

public auto ref Placeholder(T)(auto ref ArgumentUDA!T uda, string value)
{
    uda.info.placeholder = value;
    return uda;
}

public auto ref Required(T)(auto ref ArgumentUDA!T uda)
{
    uda.info.required = true;
    return uda;
}

public auto ref Optional(T)(auto ref ArgumentUDA!T uda)
{
    uda.info.required = false;
    return uda;
}

public auto ref NumberOfValues(T)(auto ref ArgumentUDA!T uda, ulong num)
{
    uda.info.minValuesCount = num;
    uda.info.maxValuesCount = num;
    return uda;
}

public auto ref NumberOfValues(T)(auto ref ArgumentUDA!T uda, ulong min, ulong max)
{
    uda.info.minValuesCount = min;
    uda.info.maxValuesCount = max;
    return uda;
}

public auto ref MinNumberOfValues(T)(auto ref ArgumentUDA!T uda, ulong min)
{
    assert(min <= uda.info.maxValuesCount.get(ulong.max));

    uda.info.minValuesCount = min;
    return uda;
}

public auto ref MaxNumberOfValues(T)(auto ref ArgumentUDA!T uda, ulong max)
{
    assert(max >= uda.info.minValuesCount.get(0));

    uda.info.maxValuesCount = max;
    return uda;
}

unittest
{
    ArgumentUDA!(ValueParseFunctions!(void, void, void, void, void, void)) arg;
    assert(!arg.info.hideFromHelp);
    assert(!arg.info.required);
    assert(arg.info.minValuesCount.isNull);
    assert(arg.info.maxValuesCount.isNull);

    arg = arg.Description("desc").Placeholder("text");
    assert(arg.info.description.get == "desc");
    assert(arg.info.placeholder == "text");

    arg = arg.Description(() => "qwer").Placeholder("text");
    assert(arg.info.description.get == "qwer");

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

    // values shouldn't be changed
    arg.addDefaults(ArgumentUDA!(ValueParseFunctions!(void, void, void, void, void, void)).init);
    assert(arg.info.placeholder == "text");
    assert(arg.info.description.get == "qwer");
    assert(arg.info.hideFromHelp);
    assert(!arg.info.required);
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
    package LazyString description;
    package size_t[] arguments;
}

public auto ref Description(T : Group)(auto ref T group, string text)
{
    group.description = text;
    return group;
}

public auto ref Description(T : Group)(auto ref T group, string delegate() text)
{
    group.description = text;
    return group;
}

auto ArgumentGroup(string name)
{
    return Group(name);
}

unittest
{
    auto g = ArgumentGroup("name").Description("description");
    assert(g.name == "name");
    assert(g.description.get == "description");

    g = g.Description(() => "descr");
    assert(g.description.get == "descr");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package struct RestrictionGroup
{
    package string location;

    package enum Type { together, exclusive }
    package Type type;

    package size_t[] arguments;

    package bool required;
}

public auto ref Required(T : RestrictionGroup)(auto ref T group)
{
    group.required = true;
    return group;
}

public auto RequiredTogether(string file=__FILE__, uint line = __LINE__)()
{
    import std.conv: to;
    return RestrictionGroup(file~":"~line.to!string, RestrictionGroup.Type.together);
}

public auto MutuallyExclusive(string file=__FILE__, uint line = __LINE__)()
{
    import std.conv: to;
    return RestrictionGroup(file~":"~line.to!string, RestrictionGroup.Type.exclusive);
}


unittest
{
    assert(!RestrictionGroup.init.required);
    assert(RestrictionGroup.init.Required.required);
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
    package LazyString usage;
    package LazyString description;
    package LazyString shortDescription;
    package LazyString epilog;
}

public auto ref Usage(T : CommandInfo)(auto ref T cmd, string text)
{
    cmd.usage = text;
    return cmd;
}

public auto ref Usage(T : CommandInfo)(auto ref T cmd, string delegate() text)
{
    cmd.usage = text;
    return cmd;
}

public auto ref Description(T : CommandInfo)(auto ref T cmd, string text)
{
    cmd.description = text;
    return cmd;
}

public auto ref Description(T : CommandInfo)(auto ref T cmd, string delegate() text)
{
    cmd.description = text;
    return cmd;
}

public auto ref ShortDescription(T : CommandInfo)(auto ref T cmd, string text)
{
    cmd.shortDescription = text;
    return cmd;
}

public auto ref ShortDescription(T : CommandInfo)(auto ref T cmd, string delegate() text)
{
    cmd.shortDescription = text;
    return cmd;
}

public auto ref Epilog(T : CommandInfo)(auto ref T cmd, string text)
{
    cmd.epilog = text;
    return cmd;
}

public auto ref Epilog(T : CommandInfo)(auto ref T cmd, string delegate() text)
{
    cmd.epilog = text;
    return cmd;
}

unittest
{
    CommandInfo c;
    c = c.Usage("usg").Description("desc").ShortDescription("sum").Epilog("epi");
    assert(c.names == [""]);
    assert(c.usage.get == "usg");
    assert(c.description.get == "desc");
    assert(c.shortDescription.get == "sum");
    assert(c.epilog.get == "epi");
}

unittest
{
    CommandInfo c;
    c = c.Usage(() => "usg").Description(() => "desc").ShortDescription(() => "sum").Epilog(() => "epi");
    assert(c.names == [""]);
    assert(c.usage.get == "usg");
    assert(c.description.get == "desc");
    assert(c.shortDescription.get == "sum");
    assert(c.epilog.get == "epi");
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

    Config config;
    config.addHelp = false;

    auto a = CommandArguments!T(&config);
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

    Config config;
    config.addHelp = false;

    auto a = CommandArguments!T(&config);
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

    Config config;
    auto p = CommandArguments!params(&config);
    assert(p.findNamedArgument("a").arg is null);
    assert(p.findNamedArgument("b").arg !is null);
    assert(p.findNamedArgument("boo").arg !is null);
    assert(p.findPositionalArgument(0).arg !is null);
    assert(p.findPositionalArgument(1).arg is null);
    assert(p.getParseFunction!false(p.findNamedArgument("b").index) !is null);
    assert(p.getParseFunction!true(p.findNamedArgument("b").index) !is null);
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
        assert(t.color == Config.StylingMode.on);
        return 12345;
    })(["--color"]) == 12345);
    assert(CLI!T.parseArgs!((T t) {
        assert(t.color == Config.StylingMode.off);
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
        return callParser!(config, false)(receiver, args, unrecognizedArgs);
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
            res = Result.Error("Unrecognized arguments: ", args);
            config.onError(res.errorMsg);
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

        COMMAND dummy;
        string[] unrecognizedArgs;

        auto res = callParser!(config, true)(dummy, args.length == 0 ? [""] : args, unrecognizedArgs);

        return res ? res.suggestions.dup.sort.uniq.array : [];
    }

    int complete(string[] args)
    {
        import argparse.completer;
        import std.sumtype: match;

        // dmd fails with core.exception.OutOfMemoryError@core\lifetime.d(137): Memory allocation failed
        // if we call anything from CLI!(config, Complete!COMMAND) so we have to directly call parser here

        Complete!COMMAND receiver;
        string[] unrecognizedArgs;

        auto res = callParser!(config, false)(receiver, args, unrecognizedArgs);
        if(!res)
            return 1;

        if(res && unrecognizedArgs.length > 0)
        {
            config.onError("Unrecognized arguments: ", unrecognizedArgs);
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


public auto PreValidation(alias func, T)(auto ref ArgumentUDA!T uda)
{
    return ArgumentUDA!(uda.parsingFunc.changePreValidation!func)(uda.tupleof);
}

public auto Parse(alias func, T)(auto ref ArgumentUDA!T uda)
{
    return ArgumentUDA!(uda.parsingFunc.changeParse!func)(uda.tupleof);
}

public auto Validation(alias func, T)(auto ref ArgumentUDA!T uda)
{
    return ArgumentUDA!(uda.parsingFunc.changeValidation!func)(uda.tupleof);
}

public auto Action(alias func, T)(auto ref ArgumentUDA!T uda)
{
    return ArgumentUDA!(uda.parsingFunc.changeAction!func)(uda.tupleof);
}

public auto AllowNoValue(alias valueToUse, T)(auto ref ArgumentUDA!T uda)
{
    auto desc = ArgumentUDA!(uda.parsingFunc.changeNoValueAction!(() { return valueToUse; }))(uda.tupleof);
    desc.info.minValuesCount = 0;
    return desc;
}


unittest
{
    auto uda = NamedArgument().PreValidation!({});
    assert(is(typeof(uda) : ArgumentUDA!(ValueParseFunctions!(void, FUNC, void, void, void, void)), alias FUNC));
    assert(!is(FUNC == void));
}

unittest
{
    auto uda = NamedArgument().Parse!({});
    assert(is(typeof(uda) : ArgumentUDA!(ValueParseFunctions!(void, void, FUNC, void, void, void)), alias FUNC));
    assert(!is(FUNC == void));
}

unittest
{
    auto uda = NamedArgument().Validation!({});
    assert(is(typeof(uda) : ArgumentUDA!(ValueParseFunctions!(void, void, void, FUNC, void, void)), alias FUNC));
    assert(!is(FUNC == void));
}

unittest
{
    auto uda = NamedArgument().Action!({});
    assert(is(typeof(uda) : ArgumentUDA!(ValueParseFunctions!(void, void, void, void, FUNC, void)), alias FUNC));
    assert(!is(FUNC == void));
}

unittest
{
    auto uda = NamedArgument().AllowNoValue!({});
    assert(is(typeof(uda) : ArgumentUDA!(ValueParseFunctions!(void, void, void, void, void, FUNC)), alias FUNC));
    assert(!is(FUNC == void));
    assert(uda.info.minValuesCount == 0);
}


public auto RequireNoValue(alias valueToUse, T)(auto ref ArgumentUDA!T uda)
{
    auto desc = uda.AllowNoValue!valueToUse;
    desc.info.minValuesCount = 0;
    desc.info.maxValuesCount = 0;
    return desc;
}


unittest
{
    auto uda = NamedArgument().RequireNoValue!"value";
    assert(is(typeof(uda) : ArgumentUDA!(ValueParseFunctions!(void, void, void, void, void, FUNC)), alias FUNC));
    assert(!is(FUNC == void));
    assert(uda.info.minValuesCount == 0);
    assert(uda.info.maxValuesCount == 0);
}


public auto Counter(T)(auto ref ArgumentUDA!T uda)
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

    auto desc = ArgumentUDA!(CounterParsingFunction)(uda.tupleof);
    desc.info.minValuesCount = 0;
    desc.info.maxValuesCount = 0;
    return desc;
}


unittest
{
    auto uda = NamedArgument().Counter();
    assert(is(typeof(uda) : ArgumentUDA!TYPE, TYPE));
    assert(is(TYPE));
    assert(!is(TYPE == void));
    assert(uda.info.minValuesCount == 0);
    assert(uda.info.maxValuesCount == 0);

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
    if(desc.info.placeholder.length == 0)
        desc.info.placeholder = formatAllowedValues!values;

    return desc;
}


unittest
{
    assert(NamedArgument.AllowedValues!([1,3,5]).info.placeholder == "{1,3,5}");

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

@(NamedArgument
.Description("Colorize the output. If value is omitted then 'always' is used.")
.AllowedValues!(["always","auto","never"])
.NumberOfValues(0, 1)
)
package struct AnsiStylingArgument
{
    Config.StylingMode stylingMode = Config.StylingMode.autodetect;

    alias stylingMode this;

    string toString() const
    {
        import std.conv: to;
        return stylingMode.to!string;
    }

    package void set(const Config* config, Config.StylingMode mode)
    {
        config.setStylingMode(stylingMode = mode);
    }
    package static void action(ref AnsiStylingArgument receiver, RawParam param)
    {
        switch(param.value[0])
        {
            case "always":  receiver.set(param.config, Config.StylingMode.on);         return;
            case "auto":    receiver.set(param.config, Config.StylingMode.autodetect); return;
            case "never":   receiver.set(param.config, Config.StylingMode.off);        return;
            default:
        }
    }
    package static void action(ref AnsiStylingArgument receiver, Param!void param)
    {
        receiver.set(param.config, Config.StylingMode.on);
    }
    package static void finalize(ref AnsiStylingArgument receiver, const Config* config)
    {
        receiver.set(config, config.stylingMode);
    }
}

auto ansiStylingArgument()
{
    return AnsiStylingArgument.init;
}

unittest
{
    import std.conv: to;

    assert(ansiStylingArgument == AnsiStylingArgument.init);
    assert(ansiStylingArgument.toString() == Config.StylingMode.autodetect.to!string);

    Config config;
    config.setStylingModeHandlers ~= (Config.StylingMode mode) { config.stylingMode = mode; };

    AnsiStylingArgument arg;
    AnsiStylingArgument.action(arg, Param!void(&config));

    assert(config.stylingMode == Config.StylingMode.on);
    assert(arg.toString() == Config.StylingMode.on.to!string);
}

unittest
{
    auto test(string value)
    {
        Config config;
        config.setStylingModeHandlers ~= (Config.StylingMode mode) { config.stylingMode = mode; };

        AnsiStylingArgument arg;
        AnsiStylingArgument.action(arg, RawParam(&config, "", [value]));
        return config.stylingMode;
    }

    assert(test("always") == Config.StylingMode.on);
    assert(test("auto")   == Config.StylingMode.autodetect);
    assert(test("never")  == Config.StylingMode.off);
    assert(test("")       == Config.StylingMode.autodetect);
}