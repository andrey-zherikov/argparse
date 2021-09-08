module argparse;


import std.typecons: Nullable;
import std.traits;

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
    private void delegate(string s) nothrow errorHandlerFunc;

    @property auto errorHandler(void function(string s) nothrow func)
    {
        return errorHandlerFunc = (string msg) { func(msg); };
    }

    @property auto errorHandler(void delegate(string s) nothrow func)
    {
        return errorHandlerFunc = func;
    }


    private void onError(A...)(A args) const nothrow
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


struct Param(VALUE_TYPE)
{
    const Config config;
    string name;

    static if(!is(VALUE_TYPE == void))
        VALUE_TYPE value;
}

alias RawParam = Param!(string[]);


private enum ArgumentType { unknown, positional, shortName, longName }

private auto splitArgumentName(string arg, const Config config)
{
    import std.typecons : nullable;
    import std.string : indexOf;

    struct Result
    {
        ArgumentType    type = ArgumentType.unknown;
        string          name;
        string          origName;
        Nullable!string value;
    }

    if(arg.length == 0)
        return Result.init;

    if(arg[0] != config.namedArgChar)
        return Result(ArgumentType.positional, string.init, string.init, nullable(arg));

    if(arg.length == 1)
        return Result.init;

    Result result;

    auto idxAssignChar = config.assignChar == char.init ? -1 : arg.indexOf(config.assignChar);
    if(idxAssignChar < 0)
        result.origName = arg;
    else
    {
        result.origName = arg[0 .. idxAssignChar];
        result.value = nullable(arg[idxAssignChar + 1 .. $]);
    }

    if(result.origName[1] == config.namedArgChar)
    {
        result.type = ArgumentType.longName;
        result.name = result.origName[2..$];
    }
    else
    {
        result.type = ArgumentType.shortName;
        result.name = result.origName[1..$];
    }

    return result;
}

unittest
{
    import std.typecons : tuple, nullable;

    static assert(splitArgumentName("", Config.init).tupleof == tuple(ArgumentType.init, string.init, string.init, Nullable!string.init).tupleof);
    static assert(splitArgumentName("-", Config.init).tupleof == tuple(ArgumentType.init, string.init, string.init, Nullable!string.init).tupleof);
    static assert(splitArgumentName("abc=4", Config.init).tupleof == tuple(ArgumentType.positional, string.init, string.init, "abc=4").tupleof);
    static assert(splitArgumentName("-abc", Config.init).tupleof == tuple(ArgumentType.shortName, "abc", "-abc", Nullable!string.init).tupleof);
    static assert(splitArgumentName("--abc", Config.init).tupleof == tuple(ArgumentType.longName, "abc", "--abc", Nullable!string.init).tupleof);
    static assert(splitArgumentName("-abc=fd", Config.init).tupleof == tuple(ArgumentType.shortName, "abc", "-abc", "fd").tupleof);
    static assert(splitArgumentName("--abc=fd", Config.init).tupleof == tuple(ArgumentType.longName, "abc", "--abc", "fd").tupleof);
    static assert(splitArgumentName("-abc=", Config.init).tupleof == tuple(ArgumentType.shortName, "abc", "-abc", nullable("")).tupleof);
    static assert(splitArgumentName("--abc=", Config.init).tupleof == tuple(ArgumentType.longName, "abc", "--abc", nullable("")).tupleof);
    static assert(splitArgumentName("-=abc", Config.init).tupleof == tuple(ArgumentType.shortName, string.init, "-", "abc").tupleof);
    static assert(splitArgumentName("--=abc", Config.init).tupleof == tuple(ArgumentType.longName, string.init, "--", "abc").tupleof);
}


private template defaultValuesCount(T)
if(!is(T == void))
{
    import std.traits;

    static if(isBoolean!T)
    {
        enum min = 0;
        enum max = 1;
    }
    else static if(isSomeString!T || isScalarType!T)
    {
        enum min = 1;
        enum max = 1;
    }
    else static if(isStaticArray!T)
    {
        enum min = 1;
        enum max = T.length;
    }
    else static if(isArray!T || isAssociativeArray!T)
    {
        enum min = 1;
        enum max = ulong.max;
    }
    else static if(is(T == function))
    {
        // ... function()
        static if(__traits(compiles, { T(); }))
        {
            enum min = 0;
            enum max = 0;
        }
        // ... function(string value)
        else static if(__traits(compiles, { T(string.init); }))
        {
            enum min = 1;
            enum max = 1;
        }
        // ... function(string[] value)
        else static if(__traits(compiles, { T([string.init]); }))
        {
            enum min = 0;
            enum max = ulong.max;
        }
        // ... function(RawParam param)
        else static if(__traits(compiles, { T(RawParam.init); }))
        {
            enum min = 1;
            enum max = ulong.max;
        }
        else
            static assert(false, "Unsupported callback: " ~ T.stringof);
    }
    else
        static assert(false, "Type is not supported: " ~ T.stringof);
}

private auto addDefaultValuesCount(T)(ArgumentInfo info)
{
    if(info.minValuesCount.isNull) info.minValuesCount = defaultValuesCount!T.min;
    if(info.maxValuesCount.isNull) info.maxValuesCount = defaultValuesCount!T.max;

    return info;
}



private bool checkMemberWithMultiArgs(T)()
{
    static foreach (sym; getSymbolsByUDA!(T, ArgumentUDA))
        static assert(getUDAs!(__traits(getMember, T, __traits(identifier, sym)), ArgumentUDA).length == 1,
                      "Member "~T.stringof~"."~sym.stringof~" has multiple '*Argument' UDAs");

    return true;
}

private auto checkDuplicates(alias sortedRange, string errorMsg)() {
    import std.range : lockstep;
    import std.conv  : to;

    static if(sortedRange.length >= 2)
        static foreach(value1, value2; lockstep(sortedRange[0..$-1], sortedRange[1..$]))
            static assert(value1 != value2, errorMsg ~ value1.to!string);

    return true;
}

private bool checkArgumentNames(T)()
{
    enum names = () {
        import std.algorithm : sort;

        string[] names;
        static foreach (sym; getSymbolsByUDA!(T, ArgumentUDA))
        {{
            enum argUDA = getUDAs!(__traits(getMember, T, __traits(identifier, sym)), ArgumentUDA)[0];

            static assert(!argUDA.info.positional || argUDA.info.names.length <= 1,
                 "Positional argument should have exactly one name: "~T.stringof~"."~sym.stringof);

            static foreach (name; argUDA.info.names)
            {
                static assert(name.length > 0, "Argument name can't be empty: "~T.stringof~"."~sym.stringof);

                names ~= name;
            }
        }}

        return names.sort;
    }();

    return checkDuplicates!(names, "Argument name appears more than once: ");
}

private bool checkPositionalIndexes(T)()
{
    import std.conv  : to;
    import std.range : lockstep, iota;


    enum positions = () {
        import std.algorithm : sort;

        uint[] positions;
        static foreach (sym; getSymbolsByUDA!(T, ArgumentUDA))
        {{
            enum argUDA = getUDAs!(__traits(getMember, T, __traits(identifier, sym)), ArgumentUDA)[0];

            static if (argUDA.info.positional)
                positions ~= argUDA.info.position.get;
        }}

        return positions.sort;
    }();

    if(!checkDuplicates!(positions, "Positional arguments have duplicated position: "))
        return false;

    static foreach (i, pos; lockstep(iota(0, positions.length), positions))
        static assert(i == pos, "Positional arguments have missed position: " ~ i.to!string);

    return true;
}

private ulong countArguments(T)()
{
    return getSymbolsByUDA!(T, ArgumentUDA).length;
}

private ulong countPositionalArguments(T)()
{
    ulong count;
    static foreach (sym; getSymbolsByUDA!(T, ArgumentUDA))
        static if (getUDAs!(__traits(getMember, T, __traits(identifier, sym)), ArgumentUDA)[0].info.positional)
            count++;

    return count;
}


private struct Arguments(T)
{
    static assert(getSymbolsByUDA!(T, ArgumentUDA).length > 0, "Type "~T.stringof~" has no members with '*Argument' UDA");
    static assert(getSymbolsByUDA!(T, TrailingArgumentUDA).length <= 1, "Type "~T.stringof~" must have at most one 'TrailingArguments' UDA");

    private enum _validate = checkMemberWithMultiArgs!T && checkArgumentNames!T && checkPositionalIndexes!T;


    struct Argument
    {
        ArgumentInfo info;

        private bool function(in Config config, string argName, ref T receiver, string[] rawValues) parsingFunc;


        bool parse(in Config config, string argName, ref T receiver, string[] rawValues) const
        {
            try
            {
                return info.checkValuesCount(config, argName, rawValues.length) &&
                       parsingFunc(config, argName, receiver, rawValues);
            }
            catch(Exception e)
            {
                config.onError(argName, ": ", e.msg);
                return false;
            }
        }
    }

    immutable string function(string str) convertCase;

    static if(getSymbolsByUDA!(T, TrailingArgumentUDA).length == 1)
    {
        private void setTrailingArgs(ref T receiver, string[] rawValues) const
        {
            alias symbol = getSymbolsByUDA!(T, TrailingArgumentUDA)[0];

            static if(__traits(compiles, { __traits(getMember, receiver, symbol.stringof) = rawValues; }))
                __traits(getMember, receiver, symbol.stringof) = rawValues;
            else
                static assert(false, "Type '"~typeof(__traits(getMember, receiver, symbol.stringof)).stringof~"' of `"~
                                     T.stringof~"."~symbol.stringof~"` is not supported for 'TrailingArguments' UDA");
        }
    }

    private Argument[countArguments!T] arguments;

    // named arguments
    private ulong[string] argsNamed;

    // positional arguments
    private ulong[countPositionalArguments!T] argsPositional;

    // required arguments
    private bool[ulong] argsRequired;


    @property auto requiredArguments() const { return argsRequired; }


    this(bool caseSensitive)
    {
        if(caseSensitive)
            convertCase = s => s;
        else
            convertCase = (string str)
            {
                import std.uni : toUpper;
                return str.toUpper;
            };

        ulong idx = 0;

        static foreach(sym; getSymbolsByUDA!(T, ArgumentUDA))
        {{
            alias member = __traits(getMember, T, __traits(identifier, sym));

            enum argUDA = getUDAs!(member, ArgumentUDA)[0];

            static if(argUDA.info.positional)
                argsPositional[argUDA.info.position.get] = idx;
            else
                static foreach (name; argUDA.info.names)
                    argsNamed[convertCase(name)] = idx;

            static if(argUDA.info.required)
                argsRequired[idx] = true;

            enum arg = Argument(
                    () {
                        auto info = argUDA.info;

                        static if(!isBoolean!(typeof(member)))
                            info.allowBooleanNegation = false;

                        static if(argUDA.info.positional && argUDA.info.names.length == 0)
                            info.names ~= sym.stringof;

                        return info.addDefaultValuesCount!(typeof(member));
                    }(),
                    function (in Config config, string argName, ref T receiver, string[] rawValues)
                    {
                        auto param = RawParam(config, argName, rawValues);

                        static if(is(typeof(__traits(getMember, receiver, __traits(identifier, sym))) == function))
                        {
                            auto target = &__traits(getMember, receiver, __traits(identifier, sym));
                            return argUDA.parsingFunc.parse(target, param);
                        }
                        else
                            return argUDA.parsingFunc.parse(__traits(getMember, receiver, __traits(identifier, sym)), param);
                    }
                );

            arguments[idx++] = arg;
        }}
    }


    private auto findArgumentImpl(const ulong* pIndex) const
    {
        import std.typecons : Tuple;

        alias Result = Tuple!(ulong, "index", typeof(&arguments[0]), "arg");

        return pIndex ? Result(*pIndex, &arguments[*pIndex]) : Result(ulong.max, null);
    }

    auto findPositionalArgument(ulong position) const
    {
        return findArgumentImpl(position < argsPositional.length ? &argsPositional[position] : null);
    }

    auto findNamedArgument(string name) const
    {
        return findArgumentImpl(convertCase(name) in argsNamed);
    }

}

unittest
{
    struct T
    {
        @(NamedArgument("a"))
        int a;
        @(NamedArgument("b").Optional())
        int b;
        @(NamedArgument("c").Required())
        int c;
        @(NamedArgument("d"))
        int d;
        @(NamedArgument("e").Required())
        int e;
        @(NamedArgument("f"))
        int f;
    }
    static assert(Arguments!T(true).requiredArguments.keys == [2,4]);
}

unittest
{
    struct T0
    {
        int a;
    }
    static assert(!__traits(compiles, { Arguments!T0(true); }));

    struct T1
    {
        @(NamedArgument("1"))
        @(NamedArgument("2"))
        int a;
    }
    static assert(!__traits(compiles, { Arguments!T1(true); }));

    struct T2
    {
        @(NamedArgument("1"))
        int a;
        @(NamedArgument("1"))
        int b;
    }
    static assert(!__traits(compiles, { Arguments!T1(true); }));

    struct T3
    {
        @(PositionalArgument(0)) int a;
        @(PositionalArgument(0)) int b;
    }
    static assert(!__traits(compiles, { Arguments!T3(true); }));

    struct T4
    {
        @(PositionalArgument(0)) int a;
        @(PositionalArgument(2)) int b;
    }
    static assert(!__traits(compiles, { Arguments!T4(true); }));
}

private void checkArgumentName(T)(char namedArgChar)
{
    import std.exception: enforce;

    static foreach(sym; getSymbolsByUDA!(T, ArgumentUDA))
        static foreach(name; getUDAs!(__traits(getMember, T, __traits(identifier, sym)), ArgumentUDA)[0].info.names)
            enforce(name[0] != namedArgChar, "Name of argument should not begin with '"~namedArgChar~"': "~name);
}

private auto consumeValuesFromCLI(ref string[] args, in ArgumentInfo argumentInfo, in Config config)
{
    import std.range: empty, front, popFront;

    immutable minValuesCount = argumentInfo.minValuesCount.get;
    immutable maxValuesCount = argumentInfo.maxValuesCount.get;

    string[] values;

    if(minValuesCount > 0)
    {
        if(minValuesCount < args.length)
        {
            values = args[0..minValuesCount];
            args = args[minValuesCount..$];
        }
        else
        {
            values = args;
            args = [];
        }
    }

    while(!args.empty &&
        values.length < maxValuesCount &&
        (config.endOfArgs.length == 0 || args.front != config.endOfArgs) &&
        (args.front.length == 0 || args.front[0] != config.namedArgChar))
    {
        values ~= args.front;
        args.popFront();
    }

    return values;
}


struct ParseCLIResult(T)
{
    Arguments!T arguments;

    int resultCode = 1;  // 0 if parsing succeeded

    bool opCast(type)() if (is(type == bool))
    {
        return resultCode == 0;
    }


    private this(in Config config)
    {
        arguments = Arguments!T(config.caseSensitive);
    }

    private auto setSuccess()
    {
        resultCode = 0;
        return this;
    }

    private auto setResultCode(int code)
    {
        resultCode = code;
        return this;
    }
}

ParseCLIResult!T parseCLIKnownArgs(T)(ref T receiver,
                                      string[] args,
                                      out string[] unrecognizedArgs,
                                      in Config config = Config.init)
{
    import std.range: empty, front, popFront, join;
    import std.typecons : tuple;

    checkArgumentName!T(config.namedArgChar);

    auto result = ParseCLIResult!T(config);

    auto requiredArgs = result.arguments.requiredArguments.dup;

    alias parseNamedArg = (arg, res) {
        args.popFront();

        auto values = arg.value.isNull ? consumeValuesFromCLI(args, res.arg.info, config) : [ arg.value.get ];

        if(!res.arg.parse(config, arg.origName, receiver, values))
            return false;

        requiredArgs.remove(res.index);

        return true;
    };

    ulong positionalArgIdx = 0;

    while(!args.empty)
    {
        if(config.endOfArgs.length > 0 && args.front == config.endOfArgs)
        {
            // End of arguments
            static if(is(typeof(result.arguments.setTrailingArgs)))
                result.arguments.setTrailingArgs(receiver, args[1..$]);
            else
                unrecognizedArgs ~= args[1..$];
            break;
        }

        auto arg = splitArgumentName(args.front, config);

        final switch(arg.type)
        {
            case ArgumentType.positional:
            {
                auto res = result.arguments.findPositionalArgument(positionalArgIdx);
                if(res.arg is null)
                    goto case ArgumentType.unknown;

                auto values = consumeValuesFromCLI(args, res.arg.info, config);

                if(!res.arg.parse(config, res.arg.info.names[0], receiver, values))
                    return result;

                positionalArgIdx++;

                requiredArgs.remove(res.index);

                break;
            }

            case ArgumentType.longName:
            {
                if(arg.name.length == 0)
                {
                    config.onError("Empty argument name: ", args.front);
                    return result;
                }

                auto res = result.arguments.findNamedArgument(arg.name);
                if(res.arg !is null)
                {
                    if(!parseNamedArg(arg, res))
                        return result;

                    break;
                }

                import std.algorithm : startsWith;

                if(arg.name.startsWith("no-"))
                {
                    res = result.arguments.findNamedArgument(arg.name[3..$]);
                    if(res.arg !is null && res.arg.info.allowBooleanNegation)
                    {
                        args.popFront();

                        if(!res.arg.parse(config, arg.origName, receiver, ["false"]))
                            return result;

                        requiredArgs.remove(res.index);

                        break;
                    }
                }

                goto case ArgumentType.unknown;
            }

            case ArgumentType.shortName:
            {
                if(arg.name.length == 0)
                {
                    config.onError("Empty argument name: ", args.front);
                    return result;
                }

                auto res = result.arguments.findNamedArgument(arg.name);
                if(res.arg !is null)
                {
                    if(!parseNamedArg(arg, res))
                        return result;

                    break;
                }

                if(arg.name.length == 1)
                    goto case ArgumentType.unknown;

                if(!config.bundling)
                {
                    auto name = [arg.name[0]];
                    res = result.arguments.findNamedArgument(name);
                    if(res.arg is null || res.arg.info.minValuesCount != 1)
                        goto case ArgumentType.unknown;

                    if(!res.arg.parse(config, "-"~name, receiver, [arg.name[1..$]]))
                        return result;

                    requiredArgs.remove(res.index);

                    args.popFront();
                    break;
                }
                else
                {
                    while(arg.name.length > 0)
                    {
                        auto name = [arg.name[0]];
                        res = result.arguments.findNamedArgument(name);
                        if(res.arg is null)
                            goto case ArgumentType.unknown;

                        if(res.arg.info.minValuesCount == 0)
                        {
                            if(!res.arg.parse(config, "-"~name, receiver, []))
                                return result;

                            requiredArgs.remove(res.index);

                            arg.name = arg.name[1..$];
                        }
                        else if(res.arg.info.minValuesCount == 1)
                        {
                            if(!res.arg.parse(config, "-"~name, receiver, [arg.name[1..$]]))
                                return result;

                            requiredArgs.remove(res.index);

                            arg.name = [];
                        }
                        else
                        {
                            // trigger an error
                            res.arg.info.checkValuesCount(config, name, 1);
                            return result;
                        }
                    }

                    if(arg.name.length == 0)
                    {
                        args.popFront();
                        break;
                    }
                }

                goto case ArgumentType.unknown;
            }

            case ArgumentType.unknown:
                unrecognizedArgs ~= args.front;
                args.popFront();
        }
    }

    if(requiredArgs.length > 0)
    {
        import std.algorithm : map;
        config.onError("The following arguments are required: ",
            requiredArgs.keys.map!(idx => result.arguments.arguments[idx].info.names[0]).join(", "));
        return result;
    }

    return result.setSuccess();
}

ParseCLIResult!T parseCLIKnownArgs(T)(ref T receiver, ref string[] args, in Config config = Config.init)
{
    string[] unrecognizedArgs;

    auto res = parseCLIKnownArgs(receiver, args, unrecognizedArgs, config);
    if(res)
        args = unrecognizedArgs;

    return res;
}

Nullable!T parseCLIKnownArgs(T)(ref string[] args, in Config config = Config.init)
{
    import std.typecons : nullable;

    T receiver;

    return parseCLIKnownArgs(receiver, args, config) ? receiver.nullable : Nullable!T.init;
}

int parseCLIKnownArgs(T, FUNC)(string[] args, FUNC func, in Config config = Config.init, T initialValue = T.init)
if(__traits(compiles, { func(T.init, args); }))
{
    alias value = initialValue;

    auto res = parseCLIKnownArgs(value, args, config);
    if(!res)
        return int.max;

    static if(__traits(compiles, { int a = cast(int) func(value, args); }))
        return cast(int) func(value, args);
    else
    {
        func(value, args);
        return 0;
    }
}


ParseCLIResult!T parseCLIArgs(T)(ref T receiver, string[] args, in Config config = Config.init)
{
    string[] unrecognizedArgs;

    auto res = parseCLIKnownArgs(receiver, args, unrecognizedArgs, config);

    if(res && unrecognizedArgs.length > 0)
    {
        config.onError("Unrecognized arguments: ", unrecognizedArgs);
        return res.setResultCode(1);
    }

    return res;
}

Nullable!T parseCLIArgs(T)(string[] args, in Config config = Config.init)
{
    import std.typecons : nullable;

    T receiver;

    return parseCLIArgs(receiver, args, config) ? receiver.nullable : Nullable!T.init;
}

int parseCLIArgs(T, FUNC)(string[] args, FUNC func, in Config config = Config.init, T initialValue = T.init)
if(__traits(compiles, { func(T.init); }))
{
    alias value = initialValue;

    auto res = parseCLIArgs(value, args, config);
    if(!res)
        return int.max;

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
        .HelpText("Argument 'a'")
        .Validation!((int a) { return a > 3;})
        .PreValidation!((string s) { return s.length > 0;})
        .Validation!((int a) { return a > 0;})
        )
        int a;

        int no_b;

        @(NamedArgument(["b", "boo"]).HelpText("Flag boo")
        .AllowNoValue!55
        )
        int b;

        int no_c;
    }

    enum p = Arguments!params(true);
    static assert(p.findNamedArgument("a").arg is null);
    static assert(p.findNamedArgument("b").arg !is null);
    static assert(p.findNamedArgument("boo").arg !is null);
    static assert(p.findPositionalArgument(0).arg !is null);
    static assert(p.findPositionalArgument(1).arg is null);

    params args;
    p.findPositionalArgument(0).arg.parse(Config.init, "", args, ["123"]);
    p.findNamedArgument("b").arg.parse(Config.init, "", args, ["456"]);
    p.findNamedArgument("boo").arg.parse(Config.init, "", args, ["789"]);
    assert(args.a == 123);
    assert(args.b == 789);
}

unittest
{
    import std.typecons : tuple;

    struct T
    {
        @NamedArgument("a") string a;
        @NamedArgument("b") string b;
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
        @NamedArgument("a") string a;
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
        @NamedArgument("a") string a;
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
        @NamedArgument("a") string a;
    }

    auto args = [ "-a", "A", "-c", "C" ];

    assert(parseCLIKnownArgs!T(args).get == T("A"));
    assert(args == ["-c", "C"]);
}

unittest
{

    struct T
    {
        @NamedArgument("x")                      string x;
        @NamedArgument("foo")                    string foo;
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
        @NamedArgument("foo") bool foo = true;
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

        @(NamedArgument("b").Required())
        int b;
    }

    static assert(["-b", "4"].parseCLIArgs!T.get == T("not set", 4));
    assert(["-b", "4"].parseCLIArgs!T.get == T("not set", 4));
}

unittest
{
    struct T
    {
        @NamedArgument("x")   string x;
        @NamedArgument("foo") string foo;
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
        @NamedArgument("a") bool a;
        @NamedArgument("b") bool b;
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
        @NamedArgument("b") bool b;
    }

    static assert(["-b"]        .parseCLIArgs!T.get == T(true));
    static assert(["-b","true"] .parseCLIArgs!T.get == T(true));
    static assert(["-b","false"].parseCLIArgs!T.get == T(false));
    static assert(["-b=true"]   .parseCLIArgs!T.get == T(true));
    static assert(["-b=false"]  .parseCLIArgs!T.get == T(false));
    assert(["-b"]        .parseCLIArgs!T.get == T(true));
    assert(["-b","true"] .parseCLIArgs!T.get == T(true));
    assert(["-b","false"].parseCLIArgs!T.get == T(false));
    assert(["-b=true"]   .parseCLIArgs!T.get == T(true));
    assert(["-b=false"]  .parseCLIArgs!T.get == T(false));
}


private struct Parsers
{
    static auto Convert(T)(string value)
    {
        import std.conv: to;
        return value.length > 0 ? value.to!T : T.init;
    }

    static auto PassThrough(string[] values)
    {
        return values;
    }
}

unittest
{
    static assert(Parsers.Convert!int("7") == 7);
    static assert(Parsers.Convert!string("7") == "7");
    static assert(Parsers.Convert!char("7") == '7');

    static assert(Parsers.PassThrough(["7","8"]) == ["7","8"]);
}


private struct Actions
{
    static auto Assign(DEST, SRC=DEST)(ref DEST param, SRC value)
    {
        param  = value;
    }

    static auto Append(T)(ref T param, T value)
    {
        param ~= value;
    }

    static auto Extend(T)(ref T[] param, T value)
    {
        param ~= value;
    }

    static auto CallFunction(F)(ref F func, RawParam param)
    {
        // ... func()
        static if(__traits(compiles, { func(); }))
        {
            func();
        }
        // ... func(string value)
        else static if(__traits(compiles, { func(param.value[0]); }))
        {
            foreach(value; param.value)
                func(value);
        }
        // ... func(string[] value)
        else static if(__traits(compiles, { func(param.value); }))
        {
            func(param.value);
        }
        // ... func(RawParam param)
        else static if(__traits(compiles, { func(param); }))
        {
            func(param);
        }
        else
            static assert(false, "Unsupported callback: " ~ F.stringof);
    }

    static auto CallFunctionNoParam(F)(ref F func, Param!void param)
    {
        // ... func()
        static if(__traits(compiles, { func(); }))
        {
            func();
        }
        // ... func(string value)
        else static if(__traits(compiles, { func(string.init); }))
        {
            func(string.init);
        }
        // ... func(string[] value)
        else static if(__traits(compiles, { func([]); }))
        {
            func([]);
        }
        // ... func(Param!void param)
        else static if(__traits(compiles, { func(param); }))
        {
            func(param);
        }
        else
            static assert(false, "Unsupported callback: " ~ F.stringof);
    }
}

unittest
{
    int i;
    Actions.Assign!(int)(i,7);
    assert(i == 7);
}

unittest
{
    int[] i;
    Actions.Append!(int[])(i,[1,2,3]);
    Actions.Append!(int[])(i,[7,8,9]);
    assert(i == [1,2,3,7,8,9]);

    alias test = (int[] v1, int[] v2) {
        int[] res;

        Param!(int[]) param;

        alias F = Actions.Append!(int[]);
        param.value = v1;   ActionFunc!(F, int[], int[])(res, param);

        param.value = v2;   ActionFunc!(F, int[], int[])(res, param);

        return res;
    };
    static assert(test([1,2,3],[7,8,9]) == [1,2,3,7,8,9]);
}

unittest
{
    int[][] i;
    Actions.Extend!(int[])(i,[1,2,3]);
    Actions.Extend!(int[])(i,[7,8,9]);
    assert(i == [[1,2,3],[7,8,9]]);
}


// values => bool
// bool validate(T value)
// bool validate(T[i] value)
// bool validate(Param!T param)
private struct ValidateFunc(alias F, T, string funcName="Validation")
{
    static bool opCall(Param!T param)
    {
        static if(is(F == void))
        {
            return true;
        }
        else static if(__traits(compiles, { F(param); }))
        {
            // bool validate(Param!T param)
            return cast(bool) F(param);
        }
        else static if(__traits(compiles, { F(param.value); }))
        {
            // bool validate(T values)
            return cast(bool) F(param.value);
        }
        else static if(/*isArray!T &&*/ __traits(compiles, { F(param.value[0]); }))
        {
            // bool validate(T[i] value)
            foreach(value; param.value)
                if(!F(value))
                    return false;
            return true;
        }
        else
            static assert(false, funcName~" function is not supported");
    }
}

unittest
{
    auto test(alias F, T)(T[] values)
    {
        Param!(T[]) param;
        param.value = values;
        return ValidateFunc!(F, T[])(param);
    }

    // bool validate(T[] values)
    static assert(test!((string[] a) => true, string)(["1","2","3"]));
    static assert(test!((int[] a) => true, int)([1,2,3]));

    // bool validate(T value)
    static assert(test!((string a) => true, string)(["1","2","3"]));
    static assert(test!((int a) => true, int)([1,2,3]));

    // bool validate(Param!T param)
    static assert(test!((RawParam p) => true, string)(["1","2","3"]));
    static assert(test!((Param!(int[]) p) => true, int)([1,2,3]));
}

unittest
{
    static assert(ValidateFunc!(void, string[])(RawParam(Config.init, "", ["1","2","3"])));

    static assert(!__traits(compiles, { ValidateFunc!(() {}, string[])(config, "", ["1","2","3"]); }));
    static assert(!__traits(compiles, { ValidateFunc!((int,int) {}, string[])(config, "", ["1","2","3"]); }));
}


private template ParseType(alias F, T)
{
    import std.traits : Unqual;

    static if(is(F == void))
        alias ParseType = Unqual!T;
    else static if(Parameters!F.length == 0)
        static assert(false, "Parse function should take at least one parameter");
    else static if(Parameters!F.length == 1)
    {
        // T action(arg)
        alias ParseType = Unqual!(ReturnType!F);
        static assert(!is(ParseType == void), "Parse function should return value");
    }
    else static if(Parameters!F.length == 2 && is(Parameters!F[0] == Config))
    {
        // T action(Config config, arg)
        alias ParseType = Unqual!(ReturnType!F);
        static assert(!is(ParseType == void), "Parse function should return value");
    }
    else static if(Parameters!F.length == 2)
    {
        // ... action(ref T param, arg)
        alias ParseType = Parameters!F[0];
    }
    else static if(Parameters!F.length == 3)
    {
        // ... action(Config config, ref T param, arg)
        alias ParseType = Parameters!F[1];
    }
    else static if(Parameters!F.length == 4)
    {
        // ... action(Config config, string argName, ref T param, arg)
        alias ParseType = Parameters!F[2];
    }
    else
        static assert(false, "Parse function has too many parameters: "~Parameters!F.stringof);
}

unittest
{
    static assert(is(ParseType!(void, double) == double));
    static assert(!__traits(compiles, { ParseType!((){}, double) p; }));
    static assert(!__traits(compiles, { ParseType!((int,int,int,int,int){}, double) p; }));

    // T action(arg)
    static assert(is(ParseType!((int)=>3, double) == int));
    static assert(!__traits(compiles, { ParseType!((int){}, double) p; }));
    // T action(Config config, arg)
    static assert(is(ParseType!((Config config, int)=>3, double) == int));
    static assert(!__traits(compiles, { ParseType!((Config config, int){}, double) p; }));
    // ... action(ref T param, arg)
    static assert(is(ParseType!((ref int, string v) {}, double) == int));
    // ... action(Config config, ref T param, arg)
    static assert(is(ParseType!((Config config, ref int, string v) {}, double) == int));
    // ... action(Config config, string argName, ref T param, arg)
    //static assert(is(ParseType!((Config config, string argName, ref int, string v) {}, double) == int));
}


// T parse(string[] values)
// T parse(string value)
// T parse(RawParam param)
// bool parse(ref T receiver, RawParam param)
// void parse(ref T receiver, RawParam param)
private struct ParseFunc(alias F, T)
{
    alias ParseType = .ParseType!(F, T);

    static bool opCall(ref ParseType receiver, RawParam param)
    {
        static if(is(F == void))
        {
            foreach(value; param.value)
                receiver = Parsers.Convert!T(value);
            return true;
        }
        // T parse(string[] values)
        else static if(__traits(compiles, { receiver = cast(ParseType) F(param.value); }))
        {
            receiver = cast(ParseType) F(param.value);
            return true;
        }
        // T parse(string value)
        else static if(__traits(compiles, { receiver = cast(ParseType) F(param.value[0]); }))
        {
            foreach(value; param.value)
                receiver = cast(ParseType) F(value);
            return true;
        }
        // T parse(RawParam param)
        else static if(__traits(compiles, { receiver = cast(ParseType) F(param); }))
        {
            receiver = cast(ParseType) F(param);
            return true;
        }
        // bool parse(ref T receiver, RawParam param)
        // void parse(ref T receiver, RawParam param)
        else static if(__traits(compiles, { F(receiver, param); }))
        {
            static if(__traits(compiles, { auto res = cast(bool) F(receiver, param); }))
            {
                // bool parse(ref T receiver, RawParam param)
                return cast(bool) F(receiver, param);
            }
            else
            {
                // void parse(ref T receiver, RawParam param)
                F(receiver, param);
                return true;
            }
        }
        else
            static assert(false, "Parse function is not supported");
    }
}

unittest
{
    int i;
    RawParam param;
    param.value = ["1","2","3"];
    assert(ParseFunc!(void, int)(i, param));
    assert(i == 3);
}

unittest
{
    auto test(alias F, T)(string[] values)
    {
        T value;
        RawParam param;
        param.value = values;
        assert(ParseFunc!(F, T)(value, param));
        return value;
    }

    // T parse(string value)
    static assert(test!((string a) => a, string)(["1","2","3"]) == "3");

    // T parse(string[] values)
    static assert(test!((string[] a) => a, string[])(["1","2","3"]) == ["1","2","3"]);

    // T parse(RawParam param)
    static assert(test!((RawParam p) => p.value[0], string)(["1","2","3"]) == "1");

    // bool parse(ref T receiver, RawParam param)
    static assert(test!((ref string[] r, RawParam p) { r = p.value; return true; }, string[])(["1","2","3"]) == ["1","2","3"]);

    // void parse(ref T receiver, RawParam param)
    static assert(test!((ref string[] r, RawParam p) { r = p.value; }, string[])(["1","2","3"]) == ["1","2","3"]);
}


// bool action(ref T receiver, ParseType value)
// void action(ref T receiver, ParseType value)
// bool action(ref T receiver, Param!ParseType param)
// void action(ref T receiver, Param!ParseType param)
private struct ActionFunc(alias F, T, ParseType)
{
    static bool opCall(ref T receiver, Param!ParseType param)
    {
        static if(is(F == void))
        {
            Actions.Assign!(T, ParseType)(receiver, param.value);
            return true;
        }
        // bool action(ref T receiver, ParseType value)
        // void action(ref T receiver, ParseType value)
        else static if(__traits(compiles, { F(receiver, param.value); }))
        {
            static if(__traits(compiles, { auto res = cast(bool) F(receiver, param.value); }))
            {
                // bool action(ref T receiver, ParseType value)
                return cast(bool) F(receiver, param.value);
            }
            else
            {
                // void action(ref T receiver, ParseType value)
                F(receiver, param.value);
                return true;
            }
        }
        // bool action(ref T receiver, Param!ParseType param)
        // void action(ref T receiver, Param!ParseType param)
        else static if(__traits(compiles, { F(receiver, param); }))
        {
            static if(__traits(compiles, { auto res = cast(bool) F(receiver, param); }))
            {
                // bool action(ref T receiver, Param!ParseType param)
                return cast(bool) F(receiver, param);
            }
            else
            {
                // void action(ref T receiver, Param!ParseType param)
                F(receiver, param);
                return true;
            }
        }
        else
            static assert(false, "Action function is not supported");
    }
}

unittest
{
    auto param(T)(T values)
    {
        Param!T param;
        param.value = values;
        return param;
    }
    auto test(alias F, T)(T values)
    {
        T receiver;
        assert(ActionFunc!(F, T, T)(receiver, param(values)));
        return receiver;
    }

    static assert(test!(void, string[])(["1","2","3"]) == ["1","2","3"]);

    static assert(!__traits(compiles, { test!(() {}, string[])(["1","2","3"]); }));
    static assert(!__traits(compiles, { test!((int,int) {}, string[])(["1","2","3"]); }));

    // bool action(ref T receiver, ParseType value)
    static assert(test!((ref string[] p, string[] a) { p=a; return true; }, string[])(["1","2","3"]) == ["1","2","3"]);

    // void action(ref T receiver, ParseType value)
    static assert(test!((ref string[] p, string[] a) { p=a; }, string[])(["1","2","3"]) == ["1","2","3"]);

    // bool action(ref T receiver, Param!ParseType param)
    static assert(test!((ref string[] p, Param!(string[]) a) { p=a.value; return true; }, string[]) (["1","2","3"]) == ["1","2","3"]);

    // void action(ref T receiver, Param!ParseType param)
    static assert(test!((ref string[] p, Param!(string[]) a) { p=a.value; }, string[])(["1","2","3"]) == ["1","2","3"]);
}


// => receiver + bool
// DEST action()
// bool action(ref DEST receiver)
// void action(ref DEST receiver)
// bool action(ref DEST receiver, Param!void param)
// void action(ref DEST receiver, Param!void param)
private struct NoValueActionFunc(alias F, T)
{
    static bool opCall(ref T receiver, Param!void param)
    {
        static if(is(F == void))
        {
            assert(false, "No-value action function is not provided");
        }
        else static if(__traits(compiles, { receiver = cast(T) F(); }))
        {
            // DEST action()
            receiver = cast(T) F();
            return true;
        }
        else static if(__traits(compiles, { F(receiver); }))
        {
            static if(__traits(compiles, { auto res = cast(bool) F(receiver); }))
            {
                // bool action(ref DEST receiver)
                return cast(bool) F(receiver);
            }
            else
            {
                // void action(ref DEST receiver)
                F(receiver);
                return true;
            }
        }
        else static if(__traits(compiles, { F(receiver, param); }))
        {
            static if(__traits(compiles, { auto res = cast(bool) F(receiver, param); }))
            {
                // bool action(ref DEST receiver, Param!void param)
                return cast(bool) F(receiver, param);
            }
            else
            {
                // void action(ref DEST receiver, Param!void param)
                F(receiver, param);
                return true;
            }
        }
        else
            static assert(false, "No-value action function has too many parameters: "~Parameters!F.stringof);
    }
}

unittest
{
    auto test(alias F, T)()
    {
        T receiver;
        assert(NoValueActionFunc!(F, T)(receiver, Param!void.init));
        return receiver;
    }

    static assert(!__traits(compiles, { NoValueActionFunc!(() {}, int); }));
    static assert(!__traits(compiles, { NoValueActionFunc!((int) {}, int); }));
    static assert(!__traits(compiles, { NoValueActionFunc!((int,int) {}, int); }));
    static assert(!__traits(compiles, { NoValueActionFunc!((int,int,int) {}, int); }));

    // DEST action()
    static assert(test!(() => 7, int) == 7);

    // bool action(ref DEST param)
    static assert(test!((ref int p) { p=7; return true; }, int) == 7);

    // void action(ref DEST param)
    static assert(test!((ref int p) { p=7; }, int) == 7);

    // bool action(ref DEST receiver, Param!void param)
    static assert(test!((ref int r, Param!void p) { r=7; return true; }, int) == 7);

    // void action(ref DEST receiver, Param!void param)
    static assert(test!((ref int r, Param!void p) { r=7; }, int) == 7);
}


private void splitValues(ref RawParam param)
{
    if(param.config.arraySep == char.init)
        return;

    import std.array : array, split;
    import std.algorithm : map, joiner;

    param.value = param.value.map!((string s) => s.split(param.config.arraySep)).joiner.array;
}

unittest
{
    alias test = (char arraySep, string[] values)
    {
        Config config;
        config.arraySep = arraySep;

        auto param = RawParam(config, "", values);

        splitValues(param);

        return param.value;
    };

    static assert(test(',', []) == []);
    static assert(test(',', ["a","b","c"]) == ["a","b","c"]);
    static assert(test(',', ["a,b","c","d,e,f"]) == ["a","b","c","d","e","f"]);
    static assert(test(' ', ["a,b","c","d,e,f"]) == ["a,b","c","d,e,f"]);
}


private struct ValueParseFunctions(alias PreProcess,
                                   alias PreValidation,
                                   alias Parse,
                                   alias Validation,
                                   alias Action,
                                   alias NoValueAction)
{
    alias changePreProcess   (alias func) = ValueParseFunctions!(      func, PreValidation, Parse, Validation, Action, NoValueAction);
    alias changePreValidation(alias func) = ValueParseFunctions!(PreProcess,          func, Parse, Validation, Action, NoValueAction);
    alias changeParse        (alias func) = ValueParseFunctions!(PreProcess, PreValidation,  func, Validation, Action, NoValueAction);
    alias changeValidation   (alias func) = ValueParseFunctions!(PreProcess, PreValidation, Parse,       func, Action, NoValueAction);
    alias changeAction       (alias func) = ValueParseFunctions!(PreProcess, PreValidation, Parse, Validation,   func, NoValueAction);
    alias changeNoValueAction(alias func) = ValueParseFunctions!(PreProcess, PreValidation, Parse, Validation, Action,          func);

    template addDefaults(T)
    {
        static if(is(PreProcess == void))
            alias preProc = DefaultValueParseFunctions!T;
        else
            alias preProc = DefaultValueParseFunctions!T.changePreProcess!PreProcess;

        static if(is(PreValidation == void))
            alias preVal = preProc;
        else
            alias preVal = preProc.changePreValidation!PreValidation;

        static if(is(Parse == void))
            alias parse = preVal;
        else
            alias parse = preVal.changeParse!Parse;

        static if(is(Validation == void))
            alias val = parse;
        else
            alias val = parse.changeValidation!Validation;

        static if(is(Action == void))
            alias action = val;
        else
            alias action = val.changeAction!Action;

        static if(is(NoValueAction == void))
            alias addDefaults = action;
        else
            alias addDefaults = action.changeNoValueAction!NoValueAction;
    }


    // Procedure to process (parse) the values to an argument of type T
    //  - if there is a value(s):
    //      - pre validate raw strings
    //      - parse raw strings
    //      - validate parsed values
    //      - action with values
    //  - if there is no value:
    //      - action if no value
    // Requirement: rawValues.length must be correct
    static bool parse(T)(ref T receiver, RawParam param)
    {
        return addDefaults!T.parseImpl(receiver, param);
    }
    static bool parseImpl(T)(ref T receiver, ref RawParam rawParam)
    {
        alias ParseType(T)     = .ParseType!(Parse, T);

        alias preValidation    = ValidateFunc!(PreValidation, string[], "Pre validation");
        alias parse(T)         = ParseFunc!(Parse, T);
        alias validation(T)    = ValidateFunc!(Validation, ParseType!T);
        alias action(T)        = ActionFunc!(Action, T, ParseType!T);
        alias noValueAction(T) = NoValueActionFunc!(NoValueAction, T);

        if(rawParam.value.length == 0)
        {
            return noValueAction!T(receiver, Param!void(rawParam.config, rawParam.name));
        }
        else
        {
            static if(!is(PreProcess == void))
                PreProcess(rawParam);

            if(!preValidation(rawParam))
                return false;

            auto parsedParam = Param!(ParseType!T)(rawParam.config, rawParam.name);

            if(!parse!T(parsedParam.value, rawParam))
                return false;

            if(!validation!T(parsedParam))
                return false;

            if(!action!T(receiver, parsedParam))
                return false;

            return true;
        }
    }
}


private template DefaultValueParseFunctions(T)
if(!is(T == void))
{
    import std.traits;
    import std.conv: to;

    static if(isSomeString!T || isNumeric!T || is(T == enum))
    {
        alias DefaultValueParseFunctions = ValueParseFunctions!(
        void,   // pre process
        void,   // pre validate
        void,   // parse
        void,   // validate
        void,   // action
        void    // no-value action
        );
    }
    else static if(isBoolean!T)
    {
        alias DefaultValueParseFunctions = ValueParseFunctions!(
        void,                               // pre process
        void,                               // pre validate
        (string value)                      // parse
        {
            switch(value)
            {
                case "":    goto case;
                case "yes": goto case;
                case "y":   return true;
                case "no":  goto case;
                case "n":   return false;
                default:    return value.to!T;
            }
        },
        void,                               // validate
        void,                               // action
        (ref T result) { result = true; }   // no-value action
        );
    }
    else static if(isSomeChar!T)
    {
        alias DefaultValueParseFunctions = ValueParseFunctions!(
        void,                         // pre process
        void,                         // pre validate
        (string value)                // parse
        {
            return value.length > 0 ? value[0].to!T : T.init;
        },
        void,                         // validate
        void,                         // action
        void                          // no-value action
        );
    }
    else static if(isArray!T)
    {
        import std.traits: ForeachType;

        alias TElement = ForeachType!T;

        static if(!isArray!TElement || isSomeString!TElement)  // 1D array
        {
            static if(!isStaticArray!T)
                alias action = Actions.Append!T;
            else
                alias action = Actions.Assign!T;

            alias DefaultValueParseFunctions = DefaultValueParseFunctions!TElement
            .changePreProcess!splitValues
            .changeParse!((ref T receiver, RawParam param)
            {
                static if(!isStaticArray!T)
                {
                    if(receiver.length < param.value.length)
                        receiver.length = param.value.length;
                }

                foreach(i, value; param.value)
                {
                    if(!DefaultValueParseFunctions!TElement.parse(receiver[i],
                        RawParam(param.config, param.name, [value])))
                        return false;
                }

                return true;
            })
            .changeAction!(action)
            .changeNoValueAction!((ref T param) {});
        }
        else static if(!isArray!(ForeachType!TElement) || isSomeString!(ForeachType!TElement))  // 2D array
        {
            alias DefaultValueParseFunctions = DefaultValueParseFunctions!TElement
            .changeAction!(Actions.Extend!TElement)
            .changeNoValueAction!((ref T param) { param ~= TElement.init; });
        }
        else
        {
            static assert(false, "Multi-dimentional arrays are not supported: " ~ T.stringof);
        }
    }
    else static if(isAssociativeArray!T)
    {
        import std.string : indexOf;
        alias DefaultValueParseFunctions = ValueParseFunctions!(
        splitValues,                                                // pre process
        void,                                                       // pre validate
        Parsers.PassThrough,                                        // parse
        void,                                                       // validate
        (ref T recepient, Param!(string[]) param)                   // action
        {
            alias K = KeyType!T;
            alias V = ValueType!T;

            foreach(input; param.value)
            {
                auto j = indexOf(input, param.config.assignChar);
                if(j < 0)
                    return false;

                K key;
                if(!DefaultValueParseFunctions!K.parse(key, RawParam(param.config, param.name, [input[0 .. j]])))
                    return false;

                V value;
                if(!DefaultValueParseFunctions!V.parse(value, RawParam(param.config, param.name, [input[j + 1 .. $]])))
                    return false;

                recepient[key] = value;
            }
            return true;
        },
        (ref T param) {}    // no-value action
        );
    }
    else static if(is(T == delegate))
    {
        alias DefaultValueParseFunctions = ValueParseFunctions!(
            void,                           // pre process
            void,                           // pre validate
            Parsers.PassThrough,            // parse
            void,                           // validate
            Actions.CallFunction!T,         // action
            Actions.CallFunctionNoParam!T   // no-value action
        );
    }
     else
        static assert(false, "Type is not supported: " ~ T.stringof);
}

unittest
{
    enum MyEnum { foo, bar, }

    import std.meta: AliasSeq;
    static foreach(T; AliasSeq!(string, bool, int, double, char, MyEnum))
        static foreach(R; AliasSeq!(T, T[], T[][]))
        {{
            // ensure that this compiles
            R receiver;
            RawParam param;
            param.value = [""];
            DefaultValueParseFunctions!R.parse(receiver, param);
        }}
}

unittest
{
    alias test(R) = (string[][] values)
    {
        auto config = Config('=', ',');
        R receiver;
        foreach(value; values)
        {
            assert(DefaultValueParseFunctions!R.parse(receiver, RawParam(config, "", value)));
        }
        return receiver;
    };

    static assert(test!(string[])([["1","2","3"], [], ["4"]]) == ["1","2","3","4"]);
    static assert(test!(string[][])([["1","2","3"], [], ["4"]]) == [["1","2","3"],[],["4"]]);

    static assert(test!(string[string])([["a=bar","b=foo"], [], ["b=baz","c=boo"]]) == ["a":"bar", "b":"baz", "c":"boo"]);

    static assert(test!(string[])([["1,2,3"], [], ["4"]]) == ["1","2","3","4"]);
    static assert(test!(string[string])([["a=bar,b=foo"], [], ["b=baz,c=boo"]]) == ["a":"bar", "b":"baz", "c":"boo"]);

    static assert(test!(int[])([["1","2","3"], [], ["4"]]) == [1,2,3,4]);
    static assert(test!(int[][])([["1","2","3"], [], ["4"]]) == [[1,2,3],[],[4]]);

}

unittest
{
    import std.math: isNaN;
    enum MyEnum { foo, bar, }

    alias test(T) = (string[] values)
    {
        T receiver;
        RawParam param;
        param.value = values;
        assert(DefaultValueParseFunctions!T.parse(receiver, param));
        return receiver;
    };

    static assert(test!string([""]) == "");
    static assert(test!string(["foo"]) == "foo");
    static assert(isNaN(test!double([""])));
    static assert(test!double(["-12.34"]) == -12.34);
    static assert(test!double(["12.34"]) == 12.34);
    static assert(test!uint(["1234"]) == 1234);
    static assert(test!int([""]) == int.init);
    static assert(test!int(["-1234"]) == -1234);
    static assert(test!char([""]) == char.init);
    static assert(test!char(["f"]) == 'f');
    static assert(test!bool([]) == true);
    static assert(test!bool([""]) == true);
    static assert(test!bool(["yes"]) == true);
    static assert(test!bool(["y"]) == true);
    static assert(test!bool(["true"]) == true);
    static assert(test!bool(["no"]) == false);
    static assert(test!bool(["n"]) == false);
    static assert(test!bool(["false"]) == false);
    static assert(test!MyEnum(["foo"]) == MyEnum.foo);
    static assert(test!MyEnum(["bar"]) == MyEnum.bar);
    static assert(test!(MyEnum[])(["bar","foo"]) == [MyEnum.bar, MyEnum.foo]);
    static assert(test!(string[string])(["a=bar","b=foo"]) == ["a":"bar", "b":"foo"]);
    static assert(test!(MyEnum[string])(["a=bar","b=foo"]) == ["a":MyEnum.bar, "b":MyEnum.foo]);
    static assert(test!(int[MyEnum])(["bar=3","foo=5"]) == [MyEnum.bar:3, MyEnum.foo:5]);
}


private struct ArgumentInfo
{
    string[] names;

    string helpText;

    bool hideFromHelp = false;      // if true then this argument is not printed on help page

    bool required;

    Nullable!uint position;

    @property bool positional() const { return !position.isNull; }

    Nullable!ulong minValuesCount;
    Nullable!ulong maxValuesCount;

    private bool checkValuesCount(in Config config, string argName, ulong count) const
    {
        immutable min = minValuesCount.get;
        immutable max = maxValuesCount.get;

        // override for boolean flags
        if(allowBooleanNegation && count == 1)
            return true;

        if(min == max && count != min)
        {
            config.onError("argument ",argName,": expected ",min,min == 1 ? " value" : " values");
            return false;
        }
        if(count < min)
        {
            config.onError("argument ",argName,": expected at least ",min,min == 1 ? " value" : " values");
            return false;
        }
        if(count > max)
        {
            config.onError("argument ",argName,": expected at most ",max,max == 1 ? " value" : " values");
            return false;
        }

        return true;
    }

    private bool allowBooleanNegation = true;
}



private struct ArgumentUDA(alias ValueParseFunctions)
{
    ArgumentInfo info;

    alias parsingFunc = ValueParseFunctions;



    auto ref HelpText(string text)
    {
        info.helpText = text;
        return this;
    }

    auto ref HideFromHelp(bool hide = true)
    {
        info.hideFromHelp = hide;
        return this;
    }

    auto ref Required()
    {
        info.required = true;
        return this;
    }

    auto ref Optional()
    {
        info.required = false;
        return this;
    }

    auto ref NumberOfValues(ulong num)()
    if(num > 0)
    {
        info.minValuesCount = num;
        info.maxValuesCount = num;
        return this;
    }

    auto ref NumberOfValues(ulong min, ulong max)()
    if(0 < min && min <= max)
    {
        info.minValuesCount = min;
        info.maxValuesCount = max;
        return this;
    }

    auto ref MinNumberOfValues(ulong min)()
    if(0 < min)
    {
        assert(min <= info.maxValuesCount.get(ulong.max));

        info.minValuesCount = min;
        return this;
    }

    auto ref MaxNumberOfValues(ulong max)()
    if(0 < max)
    {
        assert(max >= info.minValuesCount.get(0));

        info.maxValuesCount = max;
        return this;
    }

    // ReverseSwitch
}

private enum bool isArgumentUDA(T) = (is(typeof(T.info) == ArgumentInfo) && is(T.parsingFunc));


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
        @(NamedArgument("a").Counter()) int a;
    }

    static assert(["-a","-a","-a"].parseCLIArgs!T.get == T(3));
    assert(["-a","-a","-a"].parseCLIArgs!T.get == T(3));
}


auto AllowedValues(alias values, ARG)(ARG arg)
{
    import std.array : assocArray;
    import std.range : cycle;

    enum valuesAA = assocArray(values, cycle([false]));

    return arg.Validation!((KeyType!(typeof(valuesAA)) value) => value in valuesAA);
}


unittest
{
    struct T
    {
        @(NamedArgument("a").AllowedValues!([1,3,5])) int a;
    }

    static assert(["-a","2"].parseCLIArgs!T.isNull);
    static assert(["-a","3"].parseCLIArgs!T.get == T(3));
    assert(["-a","2"].parseCLIArgs!T.isNull);
    assert(["-a","3"].parseCLIArgs!T.get == T(3));
}


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

auto NamedArgument(string[] name)
{
    return ArgumentUDA!(ValueParseFunctions!(void, void, void, void, void, void))(ArgumentInfo(name)).Optional();
}

auto NamedArgument(string name)
{
    return ArgumentUDA!(ValueParseFunctions!(void, void, void, void, void, void))(ArgumentInfo([name])).Optional();
}

private struct TrailingArgumentUDA
{
}

auto TrailingArguments()
{
    return TrailingArgumentUDA();
}

unittest
{
    struct T
    {
        @NamedArgument("a")  string a;
        @NamedArgument("b")  string b;

        @TrailingArguments() string[] args;
    }

    static assert(["-a","A","--","-b","B"].parseCLIArgs!T.get == T("A","",["-b","B"]));
    assert(["-a","A","--","-b","B"].parseCLIArgs!T.get == T("A","",["-b","B"]));
}

unittest
{
    struct T
    {
        @NamedArgument("i")  int i;
        @NamedArgument("u")  uint u;
        @NamedArgument("d")  double d;
    }

    static assert(["-i","-5","-u","8","-d","12.345"].parseCLIArgs!T.get == T(-5,8,12.345));
    assert(["-i","-5","-u","8","-d","12.345"].parseCLIArgs!T.get == T(-5,8,12.345));
}

unittest
{
    struct T
    {
        @(NamedArgument("a")) int[]   a;
        @(NamedArgument("b")) int[][] b;
    }

    static assert(["-a","1","2","3","-a","4","5"].parseCLIArgs!T.get.a == [1,2,3,4,5]);
    static assert(["-b","1","2","3","-b","4","5"].parseCLIArgs!T.get.b == [[1,2,3],[4,5]]);
    assert(["-a","1","2","3","-a","4","5"].parseCLIArgs!T.get.a == [1,2,3,4,5]);
    assert(["-b","1","2","3","-b","4","5"].parseCLIArgs!T.get.b == [[1,2,3],[4,5]]);
}

unittest
{
    struct T
    {
        @(NamedArgument("a")) int[] a;
    }

    Config cfg;
    cfg.arraySep = ',';

    assert(["-a","1,2,3","-a","4","5"].parseCLIArgs!T(cfg).get == T([1,2,3,4,5]));
}

unittest
{
    struct T
    {
        @(NamedArgument("a")) int[string] a;
    }

    static assert(["-a=foo=3","-a","boo=7"].parseCLIArgs!T.get.a == ["foo":3,"boo":7]);
    assert(["-a=foo=3","-a","boo=7"].parseCLIArgs!T.get.a == ["foo":3,"boo":7]);
}

unittest
{
    struct T
    {
        @(NamedArgument("a")) int[string] a;
    }

    Config cfg;
    cfg.arraySep = ',';

    assert(["-a=foo=3,boo=7"].parseCLIArgs!T(cfg).get.a == ["foo":3,"boo":7]);
    assert(["-a","foo=3,boo=7"].parseCLIArgs!T(cfg).get.a == ["foo":3,"boo":7]);
}

unittest
{
    struct T
    {
        enum Fruit { apple, pear };

        @(NamedArgument("a")) Fruit a;
    }

    static assert(["-a","apple"].parseCLIArgs!T.get == T(T.Fruit.apple));
    static assert(["-a=pear"].parseCLIArgs!T.get == T(T.Fruit.pear));
    assert(["-a","apple"].parseCLIArgs!T.get == T(T.Fruit.apple));
    assert(["-a=pear"].parseCLIArgs!T.get == T(T.Fruit.pear));
}

unittest
{
    struct T
    {
        @(NamedArgument("a")) string[] a;
    }

    assert(["-a","1,2,3","-a","4","5"].parseCLIArgs!T.get == T(["1,2,3","4","5"]));

    Config cfg;
    cfg.arraySep = ',';

    assert(["-a","1,2,3","-a","4","5"].parseCLIArgs!T(cfg).get == T(["1","2","3","4","5"]));
}

unittest
{
    struct T
    {
        @(NamedArgument("a").AllowNoValue  !10) int a;
        @(NamedArgument("b").RequireNoValue!20) int b;
    }

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
        @(NamedArgument("a")
         .PreValidation!((string s) { return s.length > 1 && s[0] == '!'; })
         .Parse        !((string s) { return s[1]; })
         .Validation   !((char v) { return v >= '0' && v <= '9'; })
         .Action       !((ref int a, char v) { a = v - '0'; })
        )
        int a;
    }

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

    static assert(["-a","-a","-a","-a"].parseCLIArgs!T.get.a == 4);
    assert(["-a","-a","-a","-a"].parseCLIArgs!T.get.a == 4);
}
