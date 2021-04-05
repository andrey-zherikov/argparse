module maked.cli.argparse;

import std.typecons: Nullable;
import std.traits;

public import std.typecons: Flag, Yes, No;

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
    char optionChar = '-';

    /**
       The string that conventionally marks the end of all options.
       Assigning an empty string to `endOfOptions` effectively disables it.
       Defaults to "--".
     */
    string endOfOptions = "--";

    /**
       If set then argument names are case-sensitive.
       Defaults to true.
     */
    bool caseSensitive = true;

    /**
        Single-letter options can be bundled together, i.e. "-abc" is the same as "-a -b -c".
        Disabled by default.
     */
    bool bundling = false;

    /**
       Delegate that processes error messages if they happen during argument parsing.
       By default all errors are printed to stderr.
     */
    private void delegate(string s) errorHandlerFunc;

    @property auto errorHandler(void function(string s) func)
    {
        return errorHandlerFunc = (string msg) { func(msg); };
    }

    @property auto errorHandler(void delegate(string s) func)
    {
        return errorHandlerFunc = func;
    }


    private bool onError(A...)(A args) const
    {
        import std.conv: text;
        import std.stdio: stderr, writeln;

        if(errorHandlerFunc)
            errorHandlerFunc(text!A(args));
        else
            stderr.writeln("Error: ", args);

        return false;
    }
}

unittest
{
    Config.init.onError("--just testing error func--",1,2.3,false);
    Config c;
    c.errorHandler = (string s){};
    c.onError("--just testing error func--",1,2.3,false);
}


private enum ArgumentType { unknown, positional, shortName, longName };

private auto splitArgumentName(string arg, const Config config)
{
    import std.typecons: nullable;

    struct Result
    {
        ArgumentType    type;
        string          name;
        Nullable!string value;
    }

    if(arg.length == 0)
        return Result.init;

    if(arg[0] != config.optionChar)
        return Result(ArgumentType.positional, string.init, nullable(arg));

    if(arg.length == 1)
        return Result.init;

    ArgumentType type;

    if(arg[1] == config.optionChar)
    {
        type = ArgumentType.longName;
        arg = arg[2..$];
    }
    else
    {
        type = ArgumentType.shortName;
        arg = arg[1..$];
    }

    if(config.assignChar == char.init)
        return Result(type, arg);

    import std.string : indexOf;

    auto idx = arg.indexOf(config.assignChar);
    if(idx < 0)
        return Result(type, arg);

    return Result(type, arg[0 .. idx], nullable(arg[idx + 1 .. $]));
}

unittest
{
    import std.typecons : tuple, nullable;

    static assert(splitArgumentName("", Config.init).tupleof == tuple(ArgumentType.init, string.init, Nullable!string.init).tupleof);
    static assert(splitArgumentName("-", Config.init).tupleof == tuple(ArgumentType.init, string.init, Nullable!string.init).tupleof);
    static assert(splitArgumentName("abc=4", Config.init).tupleof == tuple(ArgumentType.positional, string.init, "abc=4").tupleof);
    static assert(splitArgumentName("-abc", Config.init).tupleof == tuple(ArgumentType.shortName, "abc", Nullable!string.init).tupleof);
    static assert(splitArgumentName("--abc", Config.init).tupleof == tuple(ArgumentType.longName, "abc", Nullable!string.init).tupleof);
    static assert(splitArgumentName("-abc=fd", Config.init).tupleof == tuple(ArgumentType.shortName, "abc", "fd").tupleof);
    static assert(splitArgumentName("--abc=fd", Config.init).tupleof == tuple(ArgumentType.longName, "abc", "fd").tupleof);
    static assert(splitArgumentName("-abc=", Config.init).tupleof == tuple(ArgumentType.shortName, "abc", nullable("")).tupleof);
    static assert(splitArgumentName("--abc=", Config.init).tupleof == tuple(ArgumentType.longName, "abc", nullable("")).tupleof);
    static assert(splitArgumentName("-=abc", Config.init).tupleof == tuple(ArgumentType.shortName, string.init, "abc").tupleof);
    static assert(splitArgumentName("--=abc", Config.init).tupleof == tuple(ArgumentType.longName, string.init, "abc").tupleof);
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
    else static if(isSomeString!T || isScalarType!T || isCallable!T)
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
        static assert(getUDAs!(__traits(getMember, T, sym.stringof), ArgumentUDA).length == 1,
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
            enum argUDA = getUDAs!(__traits(getMember, T, sym.stringof), ArgumentUDA)[0];

            static assert(!argUDA.info.positional || argUDA.info.names.length == 1,
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
            enum argUDA = getUDAs!(__traits(getMember, T, sym.stringof), ArgumentUDA)[0];

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
        static if (getUDAs!(__traits(getMember, T, sym.stringof), ArgumentUDA)[0].info.positional)
            count++;

    return count;
}


private struct Arguments(T)
{
    static assert(getSymbolsByUDA!(T, ArgumentUDA).length > 0, "Type "~T.stringof~" has no members with '*Argument' UDA");

    private enum _validate = checkMemberWithMultiArgs!T && checkArgumentNames!T && checkPositionalIndexes!T;


    struct Argument
    {
        ArgumentInfo info;

        private bool function(in Config config, string argName, ref T receiver, string[] rawValues) parsingFunc;


        bool parse(in Config config, string argName, ref T receiver, string[] rawValues) const
        {
            return info.checkValuesCount(config, argName, rawValues.length) &&
                   parsingFunc(config, argName, receiver, rawValues);
        }
    }

    immutable string function(string str) convertCase;


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
            alias member =__traits(getMember, T, sym.stringof);

            enum argUDA = getUDAs!(member, ArgumentUDA)[0];

            static if(argUDA.info.positional)
                argsPositional[argUDA.info.position.get] = idx;
            else
                static foreach (name; argUDA.info.names)
                    argsNamed[convertCase(name)] = idx;

            static if(argUDA.info.required)
                argsRequired[idx] = true;

            enum arg = Argument(
                    (info) {
                        static if(!isBoolean!(typeof(member)))
                            info.allowBooleanNegation = false;

                        return info.addDefaultValuesCount!(typeof(member));
                    }(argUDA.info),
                    function (in Config config, string argName, ref T receiver, string[] rawValues)
                    {
                        return argUDA.parsingFunc.parse(config, argName, __traits(getMember, receiver, sym.stringof), rawValues);
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


private void checkArgumentName(T)(char optionChar)
{
    import std.exception: enforce;

    static foreach(sym; getSymbolsByUDA!(T, ArgumentUDA))
        static foreach(name; getUDAs!(__traits(getMember, T, sym.stringof), ArgumentUDA)[0].info.names)
            enforce(name[0] != optionChar, "Name of argument should not begin with '"~optionChar~"': "~name);
}

struct CommandLineParser(T)
{
    import std.range;
    import std.typecons : tuple;

    private immutable Config config;

    private Arguments!T arguments;


    this(in Config config)
    {
        checkArgumentName!T(config.optionChar);

        this.config = config;

        arguments = Arguments!T(config.caseSensitive);
    }

    private auto consumeValues(ref string[] args, in ArgumentInfo argumentInfo) const
    {
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
            (config.endOfOptions.length == 0 || args.front != config.endOfOptions) &&
            (args.front.length == 0 || args.front[0] != config.optionChar))
        {
            values ~= args.front;
            args.popFront();
        }

        return values;
    }

    bool parseArgs(out T receiver, string[] args)
    {
        string[] unrecognizedArgs;
        immutable res = parseKnownArgs(receiver, args, unrecognizedArgs);
        if(!res)
            return false;

        if(unrecognizedArgs.length > 0)
            return config.onError("Unrecognized arguments: ", unrecognizedArgs);

        return true;
    }

    bool parseKnownArgs(out T receiver, string[] args, out string[] unrecognizedArgs)
    {
        auto requiredArgs = arguments.requiredArguments.dup;

        alias parseNamedArg = (arg, res) {
            args.popFront();

            auto values = arg.value.isNull ? consumeValues(args, res.arg.info) : [ arg.value.get ];

            if(!res.arg.parse(config, arg.name, receiver, values))
                return false;

            requiredArgs.remove(res.index);

            return true;
        };

        ulong positionalArgIdx = 0;

        while(!args.empty)
        {
            if(config.endOfOptions.length > 0 && args.front == config.endOfOptions)
            {
                // End of arguments
                unrecognizedArgs ~= args[1..$];
                break;
            }

            auto arg = splitArgumentName(args.front, config);

            final switch(arg.type)
            {
                case ArgumentType.positional:
                {
                    auto res = arguments.findPositionalArgument(positionalArgIdx);
                    if(res.arg is null)
                        goto case ArgumentType.unknown;

                    auto values = consumeValues(args, res.arg.info);

                    if(!res.arg.parse(config, res.arg.info.names[0], receiver, values))
                        return false;

                    positionalArgIdx++;

                    requiredArgs.remove(res.index);

                    break;
                }

                case ArgumentType.longName:
                {
                    if(arg.name.length == 0)
                        return config.onError("Empty argument name: ", args.front);

                    auto res = arguments.findNamedArgument(arg.name);
                    if(res.arg !is null)
                    {
                        if(!parseNamedArg(arg, res))
                            return false;

                        break;
                    }

                    import std.algorithm : startsWith;

                    if(arg.name.startsWith("no-"))
                    {
                        res = arguments.findNamedArgument(arg.name[3..$]);
                        if(res.arg !is null && res.arg.info.allowBooleanNegation)
                        {
                            args.popFront();

                            if(!res.arg.parse(config, arg.name, receiver, ["false"]))
                                return false;

                            requiredArgs.remove(res.index);

                            break;
                        }
                    }

                    goto case ArgumentType.unknown;
                }

                case ArgumentType.shortName:
                {
                    if(arg.name.length == 0)
                        return config.onError("Empty argument name: ", args.front);

                    auto res = arguments.findNamedArgument(arg.name);
                    if(res.arg !is null)
                    {
                        if(!parseNamedArg(arg, res))
                            return false;

                        break;
                    }

                    if(arg.name.length == 1)
                        goto case ArgumentType.unknown;

                    while(arg.name.length > 0)
                    {
                        auto name = [arg.name[0]];
                        res = arguments.findNamedArgument(name);
                        if(res.arg is null)
                            goto case ArgumentType.unknown;

                        if(res.arg.info.minValuesCount == 0)
                        {
                            if(!res.arg.parse(config, name, receiver, []))
                                return false;

                            requiredArgs.remove(res.index);

                            arg.name = arg.name[1..$];
                        }
                        else if(res.arg.info.minValuesCount == 1)
                        {
                            if(!res.arg.parse(config, name, receiver, [arg.name[1..$]]))
                                return false;

                            requiredArgs.remove(res.index);

                            arg.name = [];
                        }
                        else // trigger an error
                            return res.arg.info.checkValuesCount(config, name, 1);
                    }

                    if(arg.name.length == 0)
                    {
                        args.popFront();
                        break;
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
            return config.onError("The following arguments are required: ",
                requiredArgs.keys.map!(idx => arguments.arguments[idx].info.names[0]).join(", "));
        }

        return true;
    }
}

auto createParser(T)(Config config = Config.init)
{
    return CommandLineParser!T(config);
}

unittest
{
    import std.exception;

    struct T0
    {
        int a;
    }
    static assert(!__traits(compiles, { enum p = createParser!T0; }));
    static assert(!__traits(compiles, { auto p = createParser!T0; }));

    struct T1
    {
        @(NamedArgument("1"))
        @(NamedArgument("2"))
        int a;
    }
    static assert(!__traits(compiles, { enum p = createParser!T1; }));
    static assert(!__traits(compiles, { auto p = createParser!T1; }));

    struct T2
    {
        @(NamedArgument("1"))
        int a;
        @(NamedArgument("1"))
        int b;
    }
    static assert(!__traits(compiles, { enum p = createParser!T2; }));
    static assert(!__traits(compiles, { auto p = createParser!T2; }));

    struct T3
    {
        @(NamedArgument("--"))
        int a;
    }
    static assert(!__traits(compiles, { enum p = createParser!T3; }));
    assertThrown(createParser!T3);

    struct T4
    {
        @(PositionalArgument(0, "a")) int a;
        @(PositionalArgument(0, "b")) int b;
    }
    static assert(!__traits(compiles, { enum p = createParser!T4; }));
    static assert(!__traits(compiles, { auto p = createParser!T4; }));

    struct T5
    {
        @(PositionalArgument(0, "a")) int a;
        @(PositionalArgument(2, "b")) int b;
    }
    static assert(!__traits(compiles, { enum p = createParser!T5; }));
    static assert(!__traits(compiles, { auto p = createParser!T5; }));
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

        @(NamedArgument("b", "boo").HelpText("Flag boo")
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

    auto test(T)(string[] args)
    {
        string[] unrecognizedArgs;
        T receiver;

        assert(createParser!T.parseKnownArgs(receiver, args, unrecognizedArgs));
        return tuple(receiver, unrecognizedArgs);
    }

    struct T
    {
        @NamedArgument("x")                      string x;
        @NamedArgument("foo")                    string foo;
        @(PositionalArgument(0, "a").Optional()) string a;
        @(PositionalArgument(1, "b").Optional()) string[] b;
    }
    static assert(test!T(["--foo","FOO","-x","X"]) == tuple(T("X", "FOO"), []));
    static assert(test!T(["--foo=FOO","-x=X"]) == tuple(T("X", "FOO"), []));
    static assert(test!T(["-x","X","--","--foo","FOO"]) == tuple(T("X"), ["--foo","FOO"]));
    static assert(test!T(["--foo=FOO","1","-x=X"]) == tuple(T("X", "FOO", "1"), []));
    static assert(test!T(["--foo=FOO","1","2","3","4"]) == tuple(T(string.init, "FOO", "1",["2","3","4"]), []));
    static assert(test!T(["-xX"]) == tuple(T("X"), []));

    struct T1
    {
        @(PositionalArgument(0, "a")) string[3] a;
        @(PositionalArgument(1, "b")) string[] b;
    }
    static assert(test!T1(["1","2","3","4","5","6"]) == tuple(T1(["1","2","3"],["4","5","6"]), []));

    struct T2
    {
        @NamedArgument("foo") bool foo = true;
    }
    static assert(test!T2(["--no-foo"]) == tuple(T2(false), []));
}

unittest
{
    auto test(T)(string[] args)
    {
        Config config;
        config.caseSensitive = false;

        T receiver;

        assert(createParser!T(config).parseArgs(receiver, args));
        return receiver;
    }

    struct T
    {
        @NamedArgument("x")   string x;
        @NamedArgument("foo") string foo;
    }
    static assert(test!T(["--Foo","FOO","-X","X"]) == T("X", "FOO"));
    static assert(test!T(["--FOo=FOO","-X=X"]) == T("X", "FOO"));
}

unittest
{
    import std.typecons : tuple;
    auto test(T)(string[] args)
    {
        Config config;
        config.bundling = true;

        T receiver;

        assert(createParser!T(config).parseArgs(receiver, args));
        return receiver;
    }

    auto test1(T)(string[] args)
    {
        Config config;
        config.bundling = true;

        string[] unrecognizedArgs;
        T receiver;

        assert(createParser!T(config).parseKnownArgs(receiver, args, unrecognizedArgs));
        return tuple(receiver, unrecognizedArgs);
    }

    struct T
    {
        @NamedArgument("a") bool a;
        @NamedArgument("b") bool b;
    }
    static assert(test!T(["-a","-b"]) == T(true, true));
    static assert(test!T(["-ab"]) == T(true, true));
}


struct Parsers
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


struct Actions
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

    private static auto CallFunction(T)(const ref Config config, ref T param, string[] values)
    {
        import std.algorithm : max;

        static if(__traits(compiles, { auto res = cast(bool) param(); }))
        {
            // bool F()
            foreach(i; 0 .. max(1, values.length))
                if(!cast(bool) param())
                    return false;
            return true;
        }
        else static if(__traits(compiles, { param(); }))
        {
            // void F()
            foreach(i; 0 .. max(1, values.length))
                param();
            return true;
        }
        else static if(__traits(compiles, { auto res = cast(bool) param(config); }))
        {
            // bool F(Config config)
            foreach(i; 0 .. max(1, values.length))
                if(!cast(bool) param(config))
                    return false;
            return true;
        }
        else static if(__traits(compiles, { param(config); }))
        {
            // void F(Config config)
            foreach(i; 0 .. max(1, values.length))
                param(config);
            return true;
        }
        else static if(__traits(compiles, { auto res = cast(bool) param(values); }))
        {
            // bool F(string[] values)
            return param(values);
        }
        else static if(__traits(compiles, { param(values); }))
        {
            // void F(string[] values)
            param(values);
            return true;
        }
        else static if(__traits(compiles, { auto res = cast(bool) param(values[0]); }))
        {
            // bool F(string value)
            foreach(value; values)
                if(!cast(bool) param(value))
                    return false;
            return true;
        }
        else static if(__traits(compiles, { param(values[0]); }))
        {
            // void F(string value)
            foreach(value; values)
                param(value);
            return true;
        }
        else static if(__traits(compiles, { auto res = cast(bool) param(config, values); }))
        {
            // bool F(Config config, string[] values)
            return param(config, values);
        }
        else static if(__traits(compiles, { param(config, values); }))
        {
            // void F(Config config, string[] values)
            param(config, values);
            return true;
        }
        else static if(__traits(compiles, { auto res = cast(bool) param(config, values[0]); }))
        {
            // bool F(Config config, string value)
            foreach(value; values)
                if(!cast(bool) param(config, value))
                    return false;
            return true;
        }
        else static if(__traits(compiles, { param(config, values[0]); }))
        {
            // void F(Config config, string value)
            foreach(value; values)
                param(config, value);
            return true;
        }
        else
            static assert(false);
    }

    private static bool CallFunctionNoParam(T)(const ref Config config, ref T param)
    {
        return CallFunction!T(config, param, []);
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
}

unittest
{
    int[][] i;
    Actions.Extend!(int[])(i,[1,2,3]);
    Actions.Extend!(int[])(i,[7,8,9]);
    assert(i == [[1,2,3],[7,8,9]]);
}

unittest
{
    enum test = [
    (string[] values)
    {
        int counter = 0;
        auto f = () { counter++; };
        Config config;
        assert(Actions.CallFunction!(typeof(f))(config, f, values));
        return counter;
    },
    (string[] values)
    {
        int counter = 0;
        auto f = () { counter++; return true; };
        Config config;
        assert(Actions.CallFunction!(typeof(f))(config, f, values));
        return counter;
    },
    (string[] values)
    {
        int counter = 0;
        auto f = (Config config) { counter++; };
        Config config;
        assert(Actions.CallFunction!(typeof(f))(config, f, values));
        return counter;
    },
    (string[] values)
    {
        int counter = 0;
        auto f = (const ref Config config) { counter++; return true; };
        Config config;
        assert(Actions.CallFunction!(typeof(f))(config, f, values));
        return counter;
    },
    ];

    static foreach(t; test)
    {
        static assert(t([]) == 1);
        static assert(t(["1"]) == 1);
        static assert(t(["1","2","3"]) == 3);
    }
}

unittest
{
    enum test = [
    (string[] values)
    {
        string[] v;
        auto f = (string[] s) { v = s; };
        Config config;
        assert(Actions.CallFunction!(typeof(f))(config, f, values));
        return v;
    },
    (string[] values)
    {
        string[] v;
        auto f = (string[] s) { v = s; return true; };
        Config config;
        assert(Actions.CallFunction!(typeof(f))(config, f, values));
        return v;
    },
    (string[] values)
    {
        string[] v;
        auto f = (Config config, string[] s) { v = s; };
        Config config;
        assert(Actions.CallFunction!(typeof(f))(config, f, values));
        return v;
    },
    (string[] values)
    {
        string[] v;
        auto f = (Config config, string[] s) { v = s; return true; };
        Config config;
        assert(Actions.CallFunction!(typeof(f))(config, f, values));
        return v;
    },
    (string[] values)
    {
        string[] v;
        auto f = (string s) { v ~=s; };
        Config config;
        assert(Actions.CallFunction!(typeof(f))(config, f, values));
        return v;
    },
    (string[] values)
    {
        string[] v;
        auto f = (string s) { v ~=s; return true; };
        Config config;
        assert(Actions.CallFunction!(typeof(f))(config, f, values));
        return v;
    },
    (string[] values)
    {
        string[] v;
        auto f = (Config config, string s) { v ~=s; };
        Config config;
        assert(Actions.CallFunction!(typeof(f))(config, f, values));
        return v;
    },
    (string[] values)
    {
        string[] v;
        auto f = (const ref Config config, string s) { v ~=s; return true; };
        Config config;
        assert(Actions.CallFunction!(typeof(f))(config, f, values));
        return v;
    },
    ];

    static foreach(t; test)
    {
        static assert(t([]) == []);
        static assert(t(["1"]) == ["1"]);
        static assert(t(["1","2","3"]) == ["1","2","3"]);
    }
}

// values => bool
// bool validate(T values)
// bool validate(T[i] value)
// bool validate(Config config, T values)
// bool validate(Config config, T[i] value)
private struct ValidateFunc(alias F, T, string funcName="Validation")
{
    static bool opCall(const ref Config config, string argName, T values)
    {
        static if(isArray!T)
            alias arrayElemType = typeof(values[0]);
        else
            alias arrayElemType = void;

        static if(is(F == void))
        {
            return true;
        }
        else static if(Parameters!F.length < 1)
        {
            static assert(false, funcName~" function should have at least one parameter");
        }
        else static if(Parameters!F.length == 1)
        {
            static if(__traits(compiles, { auto res = cast(bool) F(values); }))
            {
                // bool validate(T values)
                return cast(bool) F(values);
            }
            else static if(isArray!T && __traits(compiles, { auto res = cast(bool) F(values[0]); }))
            {
                // bool validate(T[i] value)
                foreach(value; values)
                    if(!F(value))
                        return false;
                return true;
            }
            else
                static assert(false, funcName~" function should accept '"~T.stringof~"'"~
                (isArray!T ? " or '"~arrayElemType.stringof~"'" : "")~
                " parameter and return bool");
        }
        else static if(Parameters!F.length == 2)
        {
            static if(__traits(compiles, { auto res = cast(bool) F(config, values); }))
            {
                // bool validate(Config config, T values)
                return cast(bool) F(config, values);
            }
            else static if(isArray!T && __traits(compiles, { auto res = cast(bool) F(config, values[0]); }))
            {
                // bool validate(Config config, T[i] value)
                foreach(value; values)
                    if(!F(config, value))
                        return false;
                return true;
            }
            else
                static assert(false, funcName~" function should accept (Config, "~T.stringof~")"~
                (isArray!T ? " or (Config, "~arrayElemType.stringof~")" : "")~
                " parameters and return bool");
        }
        else static if(Parameters!F.length == 3)
        {
            static if(__traits(compiles, { auto res = cast(bool) F(config, argName, values); }))
            {
                // bool validate(Config config, string argName, T values)
                return cast(bool) F(config, argName, values);
            }
            else static if(isArray!T && __traits(compiles, { auto res = cast(bool) F(config, argName, values[0]); }))
            {
                // bool validate(Config config, string argName, T[i] value)
                foreach(value; values)
                    if(!F(config, argName, value))
                        return false;
                return true;
            }
            else
                static assert(false, funcName~" function should accept (Config, string, "~T.stringof~")"~
                (isArray!T ? " or (Config, string, "~arrayElemType.stringof~")" : "")~
                " parameters and return bool");
        }
        else
            static assert(false, funcName~" function has too many parameters: "~Parameters!F.stringof);
    }
}

unittest
{
    auto test(alias F, T)(T[] values)
    {
        Config config;
        return ValidateFunc!(F, T[])(config, "", values);
    }

    // bool validate(T[] values)
    static assert(test!((string[] a) => true, string)(["1","2","3"]));
    static assert(test!((int[] a) => true, int)([1,2,3]));

    // bool validate(T value)
    static assert(test!((string a) => true, string)(["1","2","3"]));
    static assert(test!((int a) => true, int)([1,2,3]));

    // bool validate(Config config, T[] values)
    static assert(test!((Config config, string[] a) => true, string)(["1","2","3"]));
    static assert(test!((Config config, int[] a) => true, int)([1,2,3]));

    // bool validate(Config config, T value)
    static assert(test!((Config config, string a) => true, string)(["1","2","3"]));
    static assert(test!((Config config, int a) => true, int)([1,2,3]));
}

unittest
{
    const Config config;
    static assert(ValidateFunc!(void, string[])(config, "", ["1","2","3"]));

    static assert(!__traits(compiles, { ValidateFunc!(() {}, string[])(config, "", ["1","2","3"]); }));
    static assert(!__traits(compiles, { ValidateFunc!((int,int) {}, string[])(config, "", ["1","2","3"]); }));
}


private template ParseType(alias F, T)
{
    static if(is(F == void))
        alias ParseType = T;
    else static if(Parameters!F.length == 0)
        static assert(false, "Parse function should take at least one parameter");
    else static if(Parameters!F.length == 1)
    {
        // T action(arg)
        alias ParseType = ReturnType!F;
        static assert(!is(ReturnType!F == void), "Parse function should return value");
    }
    else static if(Parameters!F.length == 2 && is(Parameters!F[0] == Config))
    {
        // T action(Config config, arg)
        alias ParseType = ReturnType!F;
        static assert(!is(ReturnType!F == void), "Parse function should return value");
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
    static assert(is(ParseType!((Config config, string argName, ref int, string v) {}, double) == int));
}

private enum bool funcArgByRef(alias F, uint N) = (ParameterStorageClassTuple!F[N] & ParameterStorageClass.ref_) != 0;

// values => PARSE_TYPE + bool
                // T action(string[] values)
                // T action(string value)
                // T action(Config config, string[] values)
                // T action(Config config, string value)
                // bool action(ref T param, string[] values)
                // void action(ref T param, string[] values)
                // bool action(ref T param, string value)
                // void action(ref T param, string value)
                // bool action(Config config, ref T param, string[] values)
                // void action(Config config, ref T param, string[] values)
                // bool action(Config config, ref T param, string value)
                // void action(Config config, ref T param, string value)
                // bool action(Config config, string argName, ref T param, string[] values)
                // void action(Config config, string argName, ref T param, string[] values)
                // bool action(Config config, string argName, ref T param, string value)
                // void action(Config config, string argName, ref T param, string value)
private struct ParseFunc(alias F, T)
{
    alias ParseType = .ParseType!(F, T);

    static bool opCall(const ref Config config, string argName, ref ParseType param, string[] values)
    {
        static if(is(F == void))
        {
            foreach(value; values)
                param = Parsers.Convert!T( value);
            return true;
        }
        else static if(Parameters!F.length == 1)
        {
            static if(__traits(compiles, { param = cast(ParseType) F(values); }))
            {
                // T action(string[] values)
                param = cast(ParseType) F(values);
                return true;
            }
            else static if(__traits(compiles, { param = cast(ParseType) F(values[0]); }))
            {
                // T action(string value)
                foreach(value; values)
                    param = cast(ParseType) F(value);
                return true;
            }
            else
                static assert(false, "Parse function should return accept 'string' or 'string[]' "~
                "and return '"~ParseType.stringof~"' type");
        }
        else static if(Parameters!F.length == 2 && is(Parameters!F[0] == Config))
        {
            static if(__traits(compiles, { param = cast(ParseType) F(config, values); }))
            {
                // T action(Config config, string[] values)
                param = cast(ParseType) F(config, values);
                return true;
            }
            else static if(__traits(compiles, { param = cast(ParseType) F(config, values[0]); }))
            {
                // T action(Config config, string value)
                foreach(value; values)
                    param = cast(ParseType) F(config, value);
                return true;
            }
            else
                static assert(false, "Parse function should return accept "~
                "(Config, string) or (Config, string[]) "~
                "and return '"~ParseType.stringof~"' type");
        }
        else static if(Parameters!F.length == 2)
        {
            static assert(funcArgByRef!(F, 0), "Parse function should accept first parameter by ref");

            static if(__traits(compiles, { auto res = cast(bool) F(param, values); }))
            {
                // bool action(ref T param, string[] values)
                return cast(bool) F(param, values);
            }
            else static if(__traits(compiles, { F(param, values); }))
            {
                // void action(ref T param, string[] values)
                F(param, values);
                return true;
            }
            else static if(__traits(compiles, { auto res = cast(bool) F(param, values[0]); }))
            {
                // bool action(ref T param, string value)
                foreach(value; values)
                    if(!cast(bool) F(param, value))
                        return false;
                return true;
            }
            else static if(__traits(compiles, { F(param, values[0]); }))
            {
                // void action(ref T param, string value)
                foreach(value; values)
                    F(param, value);
                return true;
            }
            else
                static assert(false, "Parse function should return accept "~
                "(ref "~ParseType.stringof~", string) or "~
                "(ref "~ParseType.stringof~", string[])");
        }
        else static if(Parameters!F.length == 3)
        {
            static assert(funcArgByRef!(F, 1), "Parse function should accept second parameter by ref");

            static if(__traits(compiles, { auto res = cast(bool) F(config, param, values); }))
            {
                // bool action(Config config, ref T param, string[] values)
                return cast(bool) F(config, param, values);
            }
            else static if(__traits(compiles, { F(config, param, values); }))
            {
                // void action(Config config, ref T param, string[] values)
                F(config, param, values);
                return true;
            }
            else static if(__traits(compiles, { auto res = cast(bool) F(config, param, values[0]); }))
            {
                // bool action(Config config, ref T param, string value)
                foreach(value; values)
                    if(!cast(bool) F(config, param, value))
                        return false;
                return true;
            }
            else static if(__traits(compiles, { F(config, param, values[0]); }))
            {
                // void action(Config config, ref T param, string value)
                foreach(value; values)
                    F(config, param, value);
                return true;
            }
            else
                static assert(false, "Parse function should return accept "~
                "(Config, ref "~ParseType.stringof~", string) or "~
                "(Config, ref "~ParseType.stringof~", string[])");
        }
        else static if(Parameters!F.length == 4)
        {
            static assert(funcArgByRef!(F, 2), "Parse function should accept third parameter by ref");

            static if(__traits(compiles, { auto res = cast(bool) F(config, argName, param, values); }))
            {
                // bool action(Config config, string argName, ref T param, string[] values)
                return cast(bool) F(config, argName, param, values);
            }
            else static if(__traits(compiles, { F(config, argName, param, values); }))
            {
                // void action(Config config, string argName, ref T param, string[] values)
                F(config, argName, param, values);
                return true;
            }
            else static if(__traits(compiles, { auto res = cast(bool) F(config, argName, param, values[0]); }))
            {
                // bool action(Config config, string argName, ref T param, string value)
                foreach(value; values)
                    if(!cast(bool) F(config, argName, param, value))
                        return false;
                return true;
            }
            else static if(__traits(compiles, { F(config, argName, param, values[0]); }))
            {
                // void action(Config config, string argName, ref T param, string value)
                foreach(value; values)
                    F(config, argName, param, value);
                return true;
            }
            else
                static assert(false, "Parse function should return accept "~
                "(Config, string, ref "~ParseType.stringof~", string) or "~
                "(Config, string, ref "~ParseType.stringof~", string[])");
        }
        else
            static assert(false, "Parse function has too many parameters: "~Parameters!F.stringof);
    }
}

unittest
{
    int i;
    Config config;
    assert(ParseFunc!(void, int)(config, "", i, ["1","2","3"]));
    assert(i == 3);
}

unittest
{
    auto test(alias F, T)(string[] values)
    {
        T value;
        Config config;
        assert(ParseFunc!(F, T)(config, "", value, values));
        return value;
    }
    auto testResult(alias F, T)(string[] values)
    {
        T value;
        Config config;
        return ParseFunc!(F, T)(config, "", value, values);
    }
    const Config config;

    // T action(string value)
    static assert(test!((string a) => a, string)(["1","2","3"]) == "3");

    // T action(SRc[] values)
    static assert(test!((string[] a) => a, string[])(["1","2","3"]) == ["1","2","3"]);

    // T action(int values)  (invalid)
    static assert(!__traits(compiles, { int a; ParseFunc!((int a) => a, string[])(config, "", a, ["1","2","3"]); }));

    // T action(Config config, string value)
    static assert(test!((Config config, string a) => a, string)(["1","2","3"]) == "3");

    // T action(Config config, string[] values)
    static assert(test!((Config config, string[] a) => a, string[])(["1","2","3"]) == ["1","2","3"]);

    // T action(Config config, int values)  (invalid)
    static assert(!__traits(compiles, { int a; ParseFunc!((Config config, int a) => a, string[])(config, "", a, ["1","2","3"]); }));

    // bool action(ref T param, string   value)
    static assert(test!((ref string p, string a) { p = a; return true; }, string)(["1","2","3"]) == "3");
    static assert(!testResult!((ref string p, string a) => false, string)(["1","2","3"]));

    // void action(ref T param, string   value)
    static assert(test!((ref string p, string a) { p = a; }, string)(["1","2","3"]) == "3");

    // bool action(ref T param, string[] values)
    static assert(test!((ref string[] p, string[] a) { p = a; return true; }, string[])(["1","2","3"]) == ["1","2","3"]);
    static assert(!testResult!((ref string[] p, string[] a) => false, string[])(["1","2","3"]));

    // void action(ref T param, string[] values)
    static assert(test!((ref string[] p, string[] a) { p = a; }, string[])(["1","2","3"]) == ["1","2","3"]);

    // void action(ref T param, int values)  (invalid)
    static assert(!__traits(compiles, { int a; ParseFunc!((ref string[] p, int a) {}, string[])(config, "", a, ["1","2","3"]); }));

    // bool action(Config config, ref T param, string   value)
    static assert(test!((Config config, ref string p, string a) { p = a; return true; }, string)(["1","2","3"]) == "3");
    static assert(!testResult!((Config config, ref string p, string a) => false, string)(["1","2","3"]));

    // void action(Config config, ref T param, string   value)
    static assert(test!((Config config, ref string p, string a) { p = a; }, string)(["1","2","3"]) == "3");

    // bool action(Config config, ref T param, string[] values)
    static assert(test!((Config config, ref string[] p, string[] a) { p = a; return true; }, string[])(["1","2","3"]) == ["1","2","3"]);
    static assert(!testResult!((Config config, ref string[] p, string[] a) => false, string[])(["1","2","3"]));

    // void action(Config config, ref T param, string[] values)
    static assert(test!((Config config, ref string[] p, string[] a) { p = a; }, string[])(["1","2","3"]) == ["1","2","3"]);

    // void action(Config config, ref T param, int values)  (invalid)
    static assert(!__traits(compiles, { int a; ParseFunc!((Config config, ref string[] p, int a) {}, string[])(config, "", a, ["1","2","3"]); }));
}

unittest
{
    const Config config;
    static assert(!__traits(compiles, { string v; ParseFunc!((string a) {}, string)(config, "", v, ["1","2","3"]); }));
    static assert(!__traits(compiles, { int a; ParseFunc!(() {}, int)(config, "", a, ["1","2","3"]); }));
    static assert(!__traits(compiles, { int a; ParseFunc!((int,int,int,int) {}, int)(config, "", a, ["1","2","3"]); }));
}


// parsed values => receiver + bool
private struct ActionFunc(alias F, T, ParseType)
{
    static bool opCall(const ref Config config, string argName, ref T param, ParseType value)
    {
        static if(is(F == void))
        {
            Actions.Assign!(T, ParseType)(param, value);
            return true;
        }
        else static if(Parameters!F.length < 2)
        {
            static assert(false, "Action function should have at least two parameters");
        }
        else static if(Parameters!F.length == 2)
        {
            static assert(funcArgByRef!(F, 0), "Action function should accept first parameter by ref");

            static if(__traits(compiles, { auto res = cast(bool) F(param, value); }))
            {
                // bool action(ref T param, ParseType value)
                return cast(bool) F(param, value);
            }
            else static if(__traits(compiles, { F(param, value); }))
            {
                // void action(ref T param, ParseType value)
                F(param, value);
                return true;
            }
            else
                static assert(false, "Action function should accept "~
                "(ref "~T.stringof~", "~ParseType.stringof~") parameters "~
                "instead of "~Parameters!F.stringof);
        }
        else static if(Parameters!F.length == 3)
        {
            static assert(funcArgByRef!(F, 1), "Action function should accept second parameter by ref");

            static if(__traits(compiles, { auto res = cast(bool) F(config, param, value); }))
            {
                // bool action(Config config, ref T param, ParseType value)
                return cast(bool) F(config, param, value);
            }
            else static if(__traits(compiles, { F(config, param, value); }))
            {
                // void action(Config config, ref T param, ParseType value)
                F(config, param, value);
                return true;
            }
            else
                static assert(false, "Action function should accept "~
                "(Config, ref "~T.stringof~", "~ParseType.stringof~") parameters "~
                "instead of "~Parameters!F.stringof);
        }
        else static if(Parameters!F.length == 4)
        {
            static assert(funcArgByRef!(F, 2), "Action function should accept third parameter by ref");

            static if(__traits(compiles, { auto res = cast(bool) F(config, argName, param, value); }))
            {
                // bool action(Config config, string argName, ref T param, ParseType value)
                return cast(bool) F(config, argName, param, value);
            }
            else static if(__traits(compiles, { F(config, argName, param, value); }))
            {
                // void action(Config config, string argName, ref T param, ParseType value)
                F(config, argName, param, value);
                return true;
            }
            else
                static assert(false, "Action function should accept "~
                "(Config, string argName, ref "~T.stringof~", "~ParseType.stringof~") parameters "~
                "instead of "~Parameters!F.stringof);
        }
        else
            static assert(false, "Action function has too many parameters: "~Parameters!F.stringof);
    }
}

unittest
{
    auto test(alias F, T)(T values)
    {
        T param;
        Config config;
        assert(ActionFunc!(F, T, T)(config, "", param, values));
        return param;
    }

    static assert(test!(void, string[])(["1","2","3"]) == ["1","2","3"]);

    static assert(!__traits(compiles, { ActionFunc!(() {}, string[])(config, "", ["1","2","3"]); }));
    static assert(!__traits(compiles, { ActionFunc!((int,int) {}, string[])(config, "", ["1","2","3"]); }));

    // bool action(ref DEST param, SRC value)
    static assert(test!((ref string[] p, string[] a) { p=a; return true; }, string[])(["1","2","3"]) == ["1","2","3"]);

    // void action(ref DEST param, SRC value)
    static assert(test!((ref string[] p, string[] a) { p=a; }, string[])(["1","2","3"]) == ["1","2","3"]);

    // bool action(Config config, ref DEST param, SRC value)
    static assert(test!((Config config, ref string[] p, string[] a) { p=a; return true; }, string[])(["1","2","3"]) == ["1","2","3"]);

    // void action(Config config, ref DEST param, SRC value)
    static assert(test!((Config config, ref string[] p, string[] a) { p=a; }, string[])(["1","2","3"]) == ["1","2","3"]);
}


// => receiver + bool
private struct NoValueActionFunc(alias F, T)
{
    static bool opCall(const ref Config config, string argName, ref T param)
    {
        static if(is(F == void))
        {
            assert(false, "No-value action function is not provided");
        }
        else static if(Parameters!F.length == 0)
        {
            param = cast(T) F();
            static if(__traits(compiles, { param = cast(T) F(); }))
            {
                // DEST action()
                param = cast(T) F();
                return true;
            }
            else
                static assert(false, "No-value action function should return '"~T.stringof~"' type instead of "~ReturnType!F.stringof);
        }
        else static if(Parameters!F.length == 1)
        {
            static assert(funcArgByRef!(F, 0), "No-value action function should accept parameter by ref");

            static if(__traits(compiles, { auto res = cast(bool) F(param); }))
            {
                // bool action(ref DEST param)
                return cast(bool) F(param);
            }
            else static if(__traits(compiles, { F(param); }))
            {
                // void action(ref DEST param)
                F(param);
                return true;
            }
            else
                static assert(false, "No-value action function should accept 'ref "~T.stringof~"' parameter instead of "~Parameters!F[0].stringof);
        }
        else static if(Parameters!F.length == 2)
        {
            static assert(funcArgByRef!(F, 1), "No-value action function should accept second parameter by ref");

            static if(__traits(compiles, { auto res = cast(bool) F(config, param); }))
            {
                // bool action(Config config, ref T param)
                return cast(bool) F(config, param);
            }
            else static if(__traits(compiles, { F(config, param); }))
            {
                // void action(Config config, ref T param)
                F(config, param);
                return true;
            }
            else
                static assert(false, "No-value action function should accept (Config, ref "~T.stringof~") parameters instead of "~Parameters!F.stringof);
        }
        else static if(Parameters!F.length == 3)
        {
            static assert(funcArgByRef!(F, 2), "No-value action function should accept third parameter by ref");

            static if(__traits(compiles, { auto res = cast(bool) F(config, argName, param); }))
            {
                // bool action(Config config, string argName, ref T param)
                return cast(bool) F(config, argName, param);
            }
            else static if(__traits(compiles, { F(config, argName, param); }))
            {
                // void action(Config config, string argName, ref T param)
                F(config, argName, param);
                return true;
            }
            else
                static assert(false, "No-value action function should accept (Config, string, ref "~T.stringof~") parameters instead of "~Parameters!F.stringof);
        }
        else
            static assert(false, "No-value action function has too many parameters: "~Parameters!F.stringof);
    }
}

unittest
{
    auto test(alias F, T)()
    {
        T param;
        Config config;
        assert(NoValueActionFunc!(F, T)(config, "", param));
        return param;
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

    // bool action(Config config, ref T param)
    static assert(test!((Config config, ref int p) { p=7; return true; }, int) == 7);

    // void action(Config config, ref T param)
    static assert(test!((Config config, ref int p) { p=7; }, int) == 7);
}


private string[] splitValues(Config config, string argName, string[] values)
{
    import std.array : array, split;
    import std.algorithm : map, joiner;

    return config.arraySep == char.init ?
    values :
    values.map!((string s) => s.split(config.arraySep)).joiner.array;
}

unittest
{
    static assert(splitValues(Config('=',','), "", []) == []);
    static assert(splitValues(Config('=',','), "", ["a","b","c"]) == ["a","b","c"]);
    static assert(splitValues(Config('=',','), "", ["a,b","c","d,e,f"]) == ["a","b","c","d","e","f"]);
    static assert(splitValues(Config('=',' '), "", ["a,b","c","d,e,f"]) == ["a,b","c","d,e,f"]);
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
    static bool parse(T)(const ref Config config, string argName, ref T param, string[] rawValues)
    {
        return addDefaults!T.parseImpl(config, argName, param, rawValues);
    }
    static bool parseImpl(T)(const ref Config config, string argName, ref T param, string[] rawValues)
    {
        alias ParseType(T)     = .ParseType!(Parse, T);

        alias preValidation    = ValidateFunc!(PreValidation, string[], "Pre validation");
        alias parse(T)         = ParseFunc!(Parse, T);
        alias validation(T)    = ValidateFunc!(Validation, ParseType!T);
        alias action(T)        = ActionFunc!(Action, T, ParseType!T);
        alias noValueAction(T) = NoValueActionFunc!(NoValueAction, T);

        if(rawValues.length == 0)
        {
            return noValueAction!T(config, argName, param);
        }
        else
        {
            static if(!is(PreProcess == void))
                rawValues = PreProcess(config, argName, rawValues);

            if(!preValidation(config, argName, rawValues))
                return false;

            ParseType!T parsedValue;

            if(!parse!T(config, argName, parsedValue, rawValues))
                return false;

            if(!validation!T(config, argName, parsedValue))
                return false;

            if(!action!T(config, argName, param, parsedValue))
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
    else static if(isCallable!T)
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
            .changeParse!((const ref Config config, string argName, ref T param, string[] values)
            {
                static if(!isStaticArray!T)
                {
                    if(param.length < values.length)
                        param.length = values.length;
                }

                foreach(i, value; values)
                    if(!DefaultValueParseFunctions!TElement.parse(config, argName, param[i], [value]))
                        return false;
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
        (const ref Config config, string argName, ref T param, string[] inputValues)  // action
        {
            alias K = KeyType!T;
            alias V = ValueType!T;

            foreach(input; inputValues)
            {
                auto j = indexOf(input, config.assignChar);
                if(j < 0)
                    return false;

                K key;
                if(!DefaultValueParseFunctions!K.parse(config, argName, key, [input[0 .. j]]))
                    return false;

                V value;
                if(!DefaultValueParseFunctions!V.parse(config, argName, value, [input[j + 1 .. $]]))
                    return false;

                param[key] = value;
            }
            return true;
        },
        (ref T param) {}    // no-value action
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
            R param;
            Config config;
            DefaultValueParseFunctions!R.parse(config, "", param, [""]);
        }}
}

unittest
{
    alias test(T) = (string[][] values)
    {
        auto config = Config('=', ',');
        T param;
        foreach(value; values)
            assert(DefaultValueParseFunctions!T.parse(config, "", param, value));
        return param;
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
        T param;
        Config config;
        assert(DefaultValueParseFunctions!T.parse(config, "", param, values));
        return param;
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

unittest
{
    bool test(alias F)()
    {
        alias T = typeof(F);
        T f = F;
        Config config;
        return DefaultValueParseFunctions!T.parse(config, "", f, [""]);
    }
    static assert(test!((){}));
    static assert(test!(() => true));
    static assert(test!((string[] s) {}));
    static assert(test!((string[] s) => true));
    static assert(test!((string   s) {}));
    static assert(test!((string   s) => true));
    static assert(test!((Config config) {}));
    static assert(test!((Config config) => true));
    static assert(test!((Config config, string[] s) {}));
    static assert(test!((Config config, string[] s) => true));
    static assert(test!((Config config, string   s) {}));
    static assert(test!((Config config, string   s) => true));
}



private struct ArgumentInfo
{
    string[] names;

    string helpText;

    string metaName;    // option name in help text

    bool hideFromHelp = false;      // if true then this argument is not printed on help page

    private Nullable!bool required_;

    @property private void required(bool value) { required_ = value; }

    @property bool required() const { return required_.get(positional); }

    Nullable!uint position;

    @property bool positional() const { return !position.isNull; }

    Nullable!ulong minValuesCount;
    Nullable!ulong maxValuesCount;

    private bool checkValuesCount(in Config config, string argName, ulong count) const
    {
        immutable min = minValuesCount.get;
        immutable max = maxValuesCount.get;

        if(minValuesCount == maxValuesCount && count != minValuesCount)
            return config.onError("argument ",argName,": expected ",minValuesCount,minValuesCount == 1 ? " value" : " values");
        if(count < minValuesCount)
            return config.onError("argument ",argName,": expected at least ",minValuesCount," values");
        if(count > maxValuesCount)
            return config.onError("argument ",argName,": expected at most ",maxValuesCount," values");

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

    auto ref MetaName(string name)
    {
        info.metaName = name;
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
        assert(max >= info.manValuesCount.get(0));

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
    desc.info.maxValuesCount = 0;
    return desc;
}

auto Counter(ARG)(ARG arg)
if(isArgumentUDA!ARG)
{
    struct CounterParsingFunction
    {
        static bool parse(T)(const ref Config config, string argName, ref T param, string[] rawValues)
        {
            assert(rawValues.length == 0);

            ++param;

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
    auto test(T)(string[] args)
    {
        T receiver;
        assert(createParser!T.parseArgs(receiver, args));
        return receiver;
    }

    struct T1
    {
        @(NamedArgument("a").Counter()) int a;
    }

    static assert(test!T1(["-a","-a","-a"]) == T1(3));
}


//auto AllowedValues(ARG, T)(ARG arg, immutable T[] values...)
//auto AllowedValues(values, ARG)(ARG arg)
//if(isArgumentUDA!ARG)
template AllowedValues(alias values)
{
    import std.array : assocArray;
    import std.range : cycle;

    enum valuesAA = assocArray(values, cycle([false]));

    auto AllowedValues(ARG)(ARG arg)
    {
        return arg.Validation!((KeyType!(typeof(valuesAA)) value) => value in valuesAA);
    }
}


unittest
{
    import std.typecons : tuple;

    auto test(T)(string[] args)
    {
        T receiver;
        auto res = createParser!T.parseArgs(receiver, args);
        return tuple(res, receiver);
    }

    struct T
    {
        @(NamedArgument("a").AllowedValues!([1,3,5])) int a;
    }

    static assert(test!T(["-a","2"]) == tuple(false, T.init));
    static assert(test!T(["-a","3"]) == tuple(true, T(3)));
}


auto PositionalArgument(uint pos, string[] name ...)
{
    auto arg = ArgumentUDA!(ValueParseFunctions!(void, void, void, void, void, void))(ArgumentInfo(name));
    arg.info.position = pos;
    return arg;
}
auto NamedArgument(string[] name ...)
{
    return ArgumentUDA!(ValueParseFunctions!(void, void, void, void, void, void))(ArgumentInfo(name));
}
