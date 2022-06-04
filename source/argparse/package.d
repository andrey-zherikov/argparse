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



private Result parseCLIKnownArgs(T)(ref T receiver,
                                    string[] args,
                                    out string[] unrecognizedArgs,
                                    const ref CommandArguments!T cmd,
                                    in Config config)
{
    auto parser = Parser(config, args);

    auto res = parser.parseAll!false(cmd, receiver);
    if(!res)
        return res;

    unrecognizedArgs = parser.unrecognizedArgs;

    return Result.Success;
}

deprecated("Use CLI!(config, COMMAND).parseKnownArgs")
Result parseCLIKnownArgs(T)(ref T receiver,
                            string[] args,
                            out string[] unrecognizedArgs,
                            in Config config)
{
    auto command = CommandArguments!T(config);
    return parseCLIKnownArgs(receiver, args, unrecognizedArgs, command, config);
}

deprecated("Use CLI!COMMAND.parseKnownArgs")
Result parseCLIKnownArgs(T)(ref T receiver,
                            string[] args,
                            out string[] unrecognizedArgs)
{
    return CLI!T.parseKnownArgs(receiver, args, unrecognizedArgs);
}

deprecated("Use CLI!(config, COMMAND).parseKnownArgs")
auto parseCLIKnownArgs(T)(ref T receiver, ref string[] args, in Config config)
{
    string[] unrecognizedArgs;

    auto res = parseCLIKnownArgs(receiver, args, unrecognizedArgs, config);
    if(res)
        args = unrecognizedArgs;

    return res;
}

deprecated("Use CLI!COMMAND.parseKnownArgs")
auto parseCLIKnownArgs(T)(ref T receiver, ref string[] args)
{
    return CLI!T.parseKnownArgs(receiver, args);
}

deprecated("Use CLI!(config, COMMAND).parseKnownArgs")
Nullable!T parseCLIKnownArgs(T)(ref string[] args, in Config config)
{
    import std.typecons : nullable;

    T receiver;

    return parseCLIKnownArgs(receiver, args, config) ? receiver.nullable : Nullable!T.init;
}

deprecated("Use CLI!COMMAND.parseKnownArgs")
Nullable!T parseCLIKnownArgs(T)(ref string[] args)
{
    import std.typecons : nullable;

    T receiver;

    return CLI!T.parseKnownArgs(receiver, args) ? receiver.nullable : Nullable!T.init;
}

deprecated("Use CLI!(config, COMMAND).parseArgs")
int parseCLIKnownArgs(T, FUNC)(string[] args, FUNC func, in Config config, T initialValue = T.init)
if(__traits(compiles, { func(T.init, args); }))
{
    alias value = initialValue;

    auto res = parseCLIKnownArgs(value, args, config);
    if(!res)
        return res.resultCode;

    static if(__traits(compiles, { int a = cast(int) func(value, args); }))
        return cast(int) func(value, args);
    else
    {
        func(value, args);
        return 0;
    }
}

deprecated("Use CLI!COMMAND.parseArgs")
int parseCLIKnownArgs(T, FUNC)(string[] args, FUNC func)
if(__traits(compiles, { func(T.init, args); }))
{
    T value;

    auto res = CLI!T.parseKnownArgs(value, args);
    if(!res)
        return res.resultCode;

    static if(__traits(compiles, { int a = cast(int) func(value, args); }))
        return cast(int) func(value, args);
    else
    {
        func(value, args);
        return 0;
    }
}


deprecated("Use CLI!(config, COMMAND).parseArgs")
auto parseCLIArgs(T)(ref T receiver, string[] args, in Config config)
{
    string[] unrecognizedArgs;

    auto res = parseCLIKnownArgs(receiver, args, unrecognizedArgs, config);

    if(res && unrecognizedArgs.length > 0)
    {
        config.onError("Unrecognized arguments: ", unrecognizedArgs);
        return Result.Failure;
    }

    return res;
}

deprecated("Use CLI!COMMAND.parseArgs")
auto parseCLIArgs(T)(ref T receiver, string[] args)
{
    return CLI!T.parseArgs(receiver, args);
}

deprecated("Use CLI!(config, COMMAND).parseArgs")
Nullable!T parseCLIArgs(T)(string[] args, in Config config)
{
    import std.typecons : nullable;

    T receiver;

    return parseCLIArgs(receiver, args, config) ? receiver.nullable : Nullable!T.init;
}

deprecated("Use CLI!COMMAND.parseArgs")
Nullable!T parseCLIArgs(T)(string[] args)
{
    import std.typecons : nullable;

    T receiver;

    return CLI!T.parseArgs(receiver, args) ? receiver.nullable : Nullable!T.init;
}

deprecated("Use CLI!(config, COMMAND).parseArgs")
int parseCLIArgs(T, FUNC)(string[] args, FUNC func, in Config config, T initialValue = T.init)
if(__traits(compiles, { func(T.init); }))
{
    alias value = initialValue;

    auto res = parseCLIArgs(value, args, config);
    if(!res)
        return res.resultCode;

    static if(__traits(compiles, { int a = cast(int) func(value); }))
        return cast(int) func(value);
    else
    {
        func(value);
        return 0;
    }
}

deprecated("Use CLI!COMMAND.parseArgs")
int parseCLIArgs(T, FUNC)(string[] args, FUNC func)
if(__traits(compiles, { func(T.init); }))
{
    T value;

    auto res = CLI!T.parseArgs(value, args);
    if(!res)
        return res.resultCode;

    static if(__traits(compiles, { int a = cast(int) func(value); }))
        return cast(int) func(value);
    else
    {
        func(value);
        return 0;
    }
}

unittest
{
    import std.exception;

    struct T
    {
        @(NamedArgument("--"))
        int a;
    }
    static assert(!__traits(compiles, { enum p = parseCLIArgs!T([]); }));
    assertThrown(parseCLIArgs!T([]));
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

    auto test(string[] args)
    {
        return tuple(args.parseCLIKnownArgs!T.get, args);
    }

    assert(test(["-a","A","--"]) == tuple(T("A"), []));
    static assert(test(["-a","A","--","-b","B"]) == tuple(T("A"), ["-b","B"]));

    {
        T args;

        args.parseCLIArgs([ "-a", "A"]);
        args.parseCLIArgs([ "-b", "B"]);

        assert(args == T("A","B"));
    }
}

unittest
{
    struct T
    {
        string a;
    }

    {
        auto test_called(string[] args)
        {
            bool called;
            auto dg = (T t) {
                called = true;
            };
            assert(args.parseCLIArgs!T(dg) == 0 || !called);
            return called;
        }

        static assert(test_called([]));
        assert(test_called([]));
        assert(!test_called(["-g"]));
    }
    {
        auto test_called(string[] args)
        {
            bool called;
            auto dg = (T t, string[] args) {
                assert(args.length == 0 || args == ["-g"]);
                called = true;
            };
            assert(args.parseCLIKnownArgs!T(dg) == 0);
            return called;
        }

        assert(test_called([]));
        static assert(test_called(["-g"]));
    }
}

unittest
{
    struct T
    {
        string a;
    }

    int my_main(T command)
    {
        // do something
        return 0;
    }

    static assert(["-a","aa"].parseCLIArgs!T(&my_main) == 0);
    assert(["-a","aa"].parseCLIArgs!T(&my_main) == 0);
}

unittest
{
    struct T
    {
        string a;
    }

    auto args = [ "-a", "A", "-c", "C" ];

    assert(parseCLIKnownArgs!T(args).get == T("A"));
    assert(args == ["-c", "C"]);
}

unittest
{

    struct T
    {
        @NamedArgument                           string x;
        @NamedArgument                           string foo;
        @(PositionalArgument(0, "a").Optional()) string a;
        @(PositionalArgument(1, "b").Optional()) string[] b;
    }
    static assert(["--foo","FOO","-x","X"].parseCLIArgs!T.get == T("X", "FOO"));
    static assert(["--foo=FOO","-x=X"].parseCLIArgs!T.get == T("X", "FOO"));
    static assert(["--foo=FOO","1","-x=X"].parseCLIArgs!T.get == T("X", "FOO", "1"));
    static assert(["--foo=FOO","1","2","3","4"].parseCLIArgs!T.get == T(string.init, "FOO", "1",["2","3","4"]));
    static assert(["-xX"].parseCLIArgs!T.get == T("X"));
    assert(["--foo","FOO","-x","X"].parseCLIArgs!T.get == T("X", "FOO"));
    assert(["--foo=FOO","-x=X"].parseCLIArgs!T.get == T("X", "FOO"));
    assert(["--foo=FOO","1","-x=X"].parseCLIArgs!T.get == T("X", "FOO", "1"));
    assert(["--foo=FOO","1","2","3","4"].parseCLIArgs!T.get == T(string.init, "FOO", "1",["2","3","4"]));
    assert(["-xX"].parseCLIArgs!T.get == T("X"));

    struct T1
    {
        @(PositionalArgument(0, "a")) string[3] a;
        @(PositionalArgument(1, "b")) string[] b;
    }
    static assert(["1","2","3","4","5","6"].parseCLIArgs!T1.get == T1(["1","2","3"],["4","5","6"]));
    assert(["1","2","3","4","5","6"].parseCLIArgs!T1.get == T1(["1","2","3"],["4","5","6"]));

    struct T2
    {
        bool foo = true;
    }
    static assert(["--no-foo"].parseCLIArgs!T2.get == T2(false));
    assert(["--no-foo"].parseCLIArgs!T2.get == T2(false));
}

unittest
{
    struct T
    {
        @(PositionalArgument(0, "a").Optional())
        string a = "not set";

        @(NamedArgument.Required())
        int b;
    }

    assert(CLI!T.parseArgs!((T t) { assert(t == T("not set", 4)); })(["-b", "4"]) == 0);
    static assert(["-b", "4"].parseCLIArgs!T.get == T("not set", 4));
    assert(["-b", "4"].parseCLIArgs!T.get == T("not set", 4));
}

unittest
{
    struct T
    {
        string x;
        string foo;
    }

    auto test(T)(string[] args)
    {
        Config config;
        config.caseSensitive = false;

        return args.parseCLIArgs!T(config).get;
    }

    static assert(test!T(["--Foo","FOO","-X","X"]) == T("X", "FOO"));
    static assert(test!T(["--FOo=FOO","-X=X"]) == T("X", "FOO"));
    assert(test!T(["--Foo","FOO","-X","X"]) == T("X", "FOO"));
    assert(test!T(["--FOo=FOO","-X=X"]) == T("X", "FOO"));
}

unittest
{
    auto test(T)(string[] args)
    {
        Config config;
        config.bundling = true;

        return args.parseCLIArgs!T(config).get;
    }

    struct T
    {
        bool a;
        bool b;
    }
    static assert(test!T(["-a","-b"]) == T(true, true));
    static assert(test!T(["-ab"]) == T(true, true));
    assert(test!T(["-a","-b"]) == T(true, true));
    assert(test!T(["-ab"]) == T(true, true));
}

unittest
{
    struct T
    {
        bool b;
    }

    assert(CLI!T.parseArgs!((T t) { assert(t == T(true)); })(["-b"]) == 0);
    assert(CLI!T.parseArgs!((T t) { assert(t == T(true)); })(["-b=true"]) == 0);
    assert(CLI!T.parseArgs!((T t) { assert(t == T(false)); })(["-b=false"]) == 0);
    static assert(["-b"]        .parseCLIArgs!T.get == T(true));
    static assert(["-b=true"]   .parseCLIArgs!T.get == T(true));
    static assert(["-b=false"]  .parseCLIArgs!T.get == T(false));
    assert(["-b"]        .parseCLIArgs!T.get == T(true));
    assert(["-b=true"]   .parseCLIArgs!T.get == T(true));
    assert(["-b=false"]  .parseCLIArgs!T.get == T(false));
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

    assert(["-c","C","cmd2","-b","B"].parseCLIArgs!T.get == T("C",null,typeof(T.cmd)(T.cmd2("B"))));
    assert(["-c","C","cmd2","--","-b","B"].parseCLIArgs!T.get == T("C",null,typeof(T.cmd)(T.cmd2("",["-b","B"]))));
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

    assert(["cmd2"].parseCLIArgs!T.get == T(typeof(T.cmd)(T.cmd2.init)));
    assert(["cmd1"].parseCLIArgs!T.get == T(typeof(T.cmd)(T.cmd1.init)));
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

    assert(["-c","C","-b","B"].parseCLIArgs!T.get == T("C",null,typeof(T.cmd)(Default!(T.cmd2)(T.cmd2("B")))));
    assert(!CLI!T.parseArgs!((_) {assert(false);})(["-h"]));
    assert(!CLI!T.parseArgs!((_) {assert(false);})(["--help"]));
}

deprecated("Use CLI!(Config, COMMAND).main or CLI!(COMMAND).main")
struct Main
{
    mixin template parseCLIKnownArgs(TYPE, alias newMain, Config config = Config.init)
    {
        mixin CLI!(config, TYPE).main!newMain;
    }

    mixin template parseCLIArgs(TYPE, alias newMain, Config config = Config.init)
    {
        mixin CLI!(config, TYPE).main!newMain;
    }
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

deprecated("Use CLI!(Config, COMMAND) or CLI!(COMMAND)")
template CLI(Config config)
{
    mixin template main(COMMAND, alias newMain)
    {
        mixin CLI!(config, COMMAND).main!newMain;
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

    assert(CLI!T.parseArgs!((T t) { assert(t == T([1,2,3],[4,5])); })(["-a","1","2","3","-b","4","5"]) == 0);
    assert(CLI!T.parseArgs!((T t) { assert(t == T([1],[4,5])); })(["-a","1","-b","4","5"]) == 0);
    assert(["-a","1","2","3","-b","4","5"].parseCLIArgs!T.get == T([1,2,3],[4,5]));
    assert(["-a","1","-b","4","5"].parseCLIArgs!T.get == T([1],[4,5]));
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

    assert(CLI!T.parseArgs!((T t) { assert(t == T(3)); })(["-a","-a","-a"]) == 0);
    static assert(["-a","-a","-a"].parseCLIArgs!T.get == T(3));
    assert(["-a","-a","-a"].parseCLIArgs!T.get == T(3));
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

    static assert(["-a","3"].parseCLIArgs!T.get == T(3));
    assert(["-a","2"].parseCLIArgs!T.isNull);
    assert(["-a","3"].parseCLIArgs!T.get == T(3));
}

unittest
{
    struct T
    {
        @(NamedArgument.AllowedValues!(["apple","pear","banana"]))
        string fruit;
    }

    assert(CLI!T.parseArgs!((T t) { assert(t == T("apple")); })(["--fruit", "apple"]) == 0);
    assert(CLI!T.parseArgs!((T t) { assert(false); })(["--fruit", "kiwi"]) != 0);    // "kiwi" is not allowed
    static assert(["--fruit", "apple"].parseCLIArgs!T.get == T("apple"));
    assert(["--fruit", "kiwi"].parseCLIArgs!T.isNull);
}

unittest
{
    enum Fruit { apple, pear, banana }
    struct T
    {
        @NamedArgument
        Fruit fruit;
    }

    static assert(["--fruit", "apple"].parseCLIArgs!T.get == T(Fruit.apple));
    assert(["--fruit", "kiwi"].parseCLIArgs!T.isNull);
}



unittest
{
    struct T
    {
        string a;
        string b;

        @TrailingArguments string[] args;
    }

    assert(CLI!T.parseArgs!((T t) { assert(t == T("A","",["-b","B"])); })(["-a","A","--","-b","B"]) == 0);
    static assert(["-a","A","--","-b","B"].parseCLIArgs!T.get == T("A","",["-b","B"]));
    assert(["-a","A","--","-b","B"].parseCLIArgs!T.get == T("A","",["-b","B"]));
}

unittest
{
    struct T
    {
        @NamedArgument int i;
        @NamedArgument(["u","u1"])  uint u;
        @NamedArgument("d","d1")  double d;
    }

    assert(CLI!T.parseArgs!((T t) { assert(t == T(-5,8,12.345)); })(["-i","-5","-u","8","-d","12.345"]) == 0);
    assert(CLI!T.parseArgs!((T t) { assert(t == T(-5,8,12.345)); })(["-i","-5","-u1","8","-d1","12.345"]) == 0);

    static assert(["-i","-5","-u","8","-d","12.345"].parseCLIArgs!T.get == T(-5,8,12.345));
    static assert(["-i","-5","-u1","8","-d1","12.345"].parseCLIArgs!T.get == T(-5,8,12.345));
    assert(["-i","-5","-u","8","-d","12.345"].parseCLIArgs!T.get == T(-5,8,12.345));
    assert(["-i","-5","-u1","8","-d1","12.345"].parseCLIArgs!T.get == T(-5,8,12.345));
}

unittest
{
    struct T
    {
        @NamedArgument int[]   a;
        @NamedArgument int[][] b;
    }

    assert(CLI!T.parseArgs!((T t) { assert(t.a == [1,2,3,4,5]); })(["-a","1","2","3","-a","4","5"]) == 0);
    assert(CLI!T.parseArgs!((T t) { assert(t.b == [[1,2,3],[4,5]]); })(["-b","1","2","3","-b","4","5"]) == 0);

    static assert(["-a","1","2","3","-a","4","5"].parseCLIArgs!T.get.a == [1,2,3,4,5]);
    static assert(["-b","1","2","3","-b","4","5"].parseCLIArgs!T.get.b == [[1,2,3],[4,5]]);
    assert(["-a","1","2","3","-a","4","5"].parseCLIArgs!T.get.a == [1,2,3,4,5]);
    assert(["-b","1","2","3","-b","4","5"].parseCLIArgs!T.get.b == [[1,2,3],[4,5]]);
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

    assert(CLI!(cfg, T).parseArgs!((T t) { assert(t == T([1,2,3,4,5])); })(["-a","1,2,3","-a","4","5"]) == 0);
    assert(["-a","1,2,3","-a","4","5"].parseCLIArgs!T(cfg).get == T([1,2,3,4,5]));
}

unittest
{
    struct T
    {
        @NamedArgument int[string] a;
    }

    assert(CLI!T.parseArgs!((T t) { assert(t == T(["foo":3,"boo":7])); })(["-a=foo=3","-a","boo=7"]) == 0);
    static assert(["-a=foo=3","-a","boo=7"].parseCLIArgs!T.get.a == ["foo":3,"boo":7]);
    assert(["-a=foo=3","-a","boo=7"].parseCLIArgs!T.get.a == ["foo":3,"boo":7]);
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

    assert(CLI!(cfg, T).parseArgs!((T t) { assert(t == T(["foo":3,"boo":7])); })(["-a=foo=3,boo=7"]) == 0);
    assert(CLI!(cfg, T).parseArgs!((T t) { assert(t == T(["foo":3,"boo":7])); })(["-a","foo=3,boo=7"]) == 0);
    assert(["-a=foo=3,boo=7"].parseCLIArgs!T(cfg).get.a == ["foo":3,"boo":7]);
    assert(["-a","foo=3,boo=7"].parseCLIArgs!T(cfg).get.a == ["foo":3,"boo":7]);
}

unittest
{
    struct T
    {
        enum Fruit { apple, pear };

        @NamedArgument Fruit a;
    }

    assert(CLI!T.parseArgs!((T t) { assert(t == T(T.Fruit.apple)); })(["-a","apple"]) == 0);
    assert(CLI!T.parseArgs!((T t) { assert(t == T(T.Fruit.pear)); })(["-a=pear"]) == 0);
    static assert(["-a","apple"].parseCLIArgs!T.get == T(T.Fruit.apple));
    static assert(["-a=pear"].parseCLIArgs!T.get == T(T.Fruit.pear));
    assert(["-a","apple"].parseCLIArgs!T.get == T(T.Fruit.apple));
    assert(["-a=pear"].parseCLIArgs!T.get == T(T.Fruit.pear));
}

unittest
{
    struct T
    {
        @NamedArgument string[] a;
    }

    assert(CLI!T.parseArgs!((T t) { assert(t == T(["1,2,3","4","5"])); })(["-a","1,2,3","-a","4","5"]) == 0);
    assert(["-a","1,2,3","-a","4","5"].parseCLIArgs!T.get == T(["1,2,3","4","5"]));

    enum cfg = {
        Config cfg;
        cfg.arraySep = ',';
        return cfg;
    }();

    assert(CLI!(cfg, T).parseArgs!((T t) { assert(t == T(["1","2","3","4","5"])); })(["-a","1,2,3","-a","4","5"]) == 0);
    assert(["-a","1,2,3","-a","4","5"].parseCLIArgs!T(cfg).get == T(["1","2","3","4","5"]));
}

unittest
{
    struct T
    {
        @(NamedArgument.AllowNoValue  !10) int a;
        @(NamedArgument.RequireNoValue!20) int b;
    }

    assert(CLI!T.parseArgs!((T t) { assert(t.a == 10); })(["-a"]) == 0);
    assert(CLI!T.parseArgs!((T t) { assert(t.b == 20); })(["-b"]) == 0);
    assert(CLI!T.parseArgs!((T t) { assert(t.a == 30); })(["-a","30"]) == 0);
    assert(CLI!T.parseArgs!((T t) { assert(false); })(["-b","30"]) != 0);
    static assert(["-a"].parseCLIArgs!T.get.a == 10);
    static assert(["-b"].parseCLIArgs!T.get.b == 20);
    static assert(["-a", "30"].parseCLIArgs!T.get.a == 30);
    assert(["-a"].parseCLIArgs!T.get.a == 10);
    assert(["-b"].parseCLIArgs!T.get.b == 20);
    assert(["-a", "30"].parseCLIArgs!T.get.a == 30);
    assert(["-b", "30"].parseCLIArgs!T.isNull);
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

    assert(CLI!T.parseArgs!((T t) { assert(t == T(4)); })(["-a","!4"]) == 0);
    static assert(["-a","!4"].parseCLIArgs!T.get.a == 4);
    assert(["-a","!4"].parseCLIArgs!T.get.a == 4);
}

unittest
{
    static struct T
    {
        int a;

        @(NamedArgument("a")) void foo() { a++; }
    }

    assert(CLI!T.parseArgs!((T t) { assert(t == T(4)); })(["-a","-a","-a","-a"]) == 0);
    static assert(["-a","-a","-a","-a"].parseCLIArgs!T.get.a == 4);
    assert(["-a","-a","-a","-a"].parseCLIArgs!T.get.a == 4);
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

    assert(parseCLIArgs!T(["-h","-s","asd"]).isNull());
    assert(parseCLIArgs!T(["-h"], (T t) { assert(false); }) == 0);

    auto args = ["-h","-s","asd"];
    assert(parseCLIKnownArgs!T(args).isNull());
    assert(args.length == 3);
    assert(parseCLIKnownArgs!T(["-h"], (T t, string[] args) { assert(false); }) == 0);
}

unittest
{
    @Command("MYPROG")
    struct T
    {
        @(NamedArgument.Required())  string s;
    }

    assert(parseCLIArgs!T([], (T t) { assert(false); }) != 0);
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

    assert(parseCLIArgs!T(["-a","a","-b","b"], (T t) { assert(false); }) != 0);
    assert(parseCLIArgs!T(["-a","a"], (T t) {}) == 0);
    assert(parseCLIArgs!T(["-b","b"], (T t) {}) == 0);
    assert(parseCLIArgs!T([], (T t) {}) == 0);
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

    assert(parseCLIArgs!T(["-a","a","-b","b"], (T t) { assert(false); }) != 0);
    assert(parseCLIArgs!T(["-a","a"], (T t) {}) == 0);
    assert(parseCLIArgs!T(["-b","b"], (T t) {}) == 0);
    assert(parseCLIArgs!T([], (T t) { assert(false); }) != 0);
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

    assert(parseCLIArgs!T(["-a","a","-b","b"], (T t) {}) == 0);
    assert(parseCLIArgs!T(["-a","a"], (T t) { assert(false); }) != 0);
    assert(parseCLIArgs!T(["-b","b"], (T t) { assert(false); }) != 0);
    assert(parseCLIArgs!T([], (T t) {}) == 0);
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

    assert(parseCLIArgs!T(["-a","a","-b","b"], (T t) {}) == 0);
    assert(parseCLIArgs!T(["-a","a"], (T t) { assert(false); }) != 0);
    assert(parseCLIArgs!T(["-b","b"], (T t) { assert(false); }) != 0);
    assert(parseCLIArgs!T([], (T t) { assert(false); }) != 0);
}


