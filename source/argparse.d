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


private struct CLIArgument
{
    struct Unknown {}
    struct Positional {}
    struct NamedShort {
        string name;
        string nameWithDash;
        string value = null;  // null when there is no value
    }
    struct NamedLong {
        string name;
        string nameWithDash;
        string value = null;  // null when there is no value
    }

    import std.sumtype: SumType;
    alias Argument = SumType!(Unknown, Positional, NamedShort, NamedLong);
}

private CLIArgument.Argument splitArgumentNameValue(string arg, const Config config = Config.init)
{
    import std.typecons : nullable;
    import std.string : indexOf;

    if(arg.length == 0)
        return CLIArgument.Argument.init;

    if(arg[0] != config.namedArgChar)
        return CLIArgument.Argument(CLIArgument.Positional.init);

    if(arg.length == 1 || arg.length == 2 && arg[1] == config.namedArgChar)
        return CLIArgument.Argument.init;

    auto idxAssignChar = config.assignChar == char.init ? -1 : arg.indexOf(config.assignChar);

    immutable string nameWithDash = idxAssignChar < 0 ? arg  : arg[0 .. idxAssignChar];
    immutable string value        = idxAssignChar < 0 ? null : arg[idxAssignChar + 1 .. $];

    return arg[1] == config.namedArgChar
        ? CLIArgument.Argument(CLIArgument.NamedLong (nameWithDash[2..$], nameWithDash, value))
        : CLIArgument.Argument(CLIArgument.NamedShort(nameWithDash[1..$], nameWithDash, value));
}

unittest
{
    import std.typecons : tuple, nullable;

    static assert(splitArgumentNameValue("") == CLIArgument.Argument(CLIArgument.Unknown.init));
    static assert(splitArgumentNameValue("-") == CLIArgument.Argument(CLIArgument.Unknown.init));
    static assert(splitArgumentNameValue("--") == CLIArgument.Argument(CLIArgument.Unknown.init));
    static assert(splitArgumentNameValue("abc=4") == CLIArgument.Argument(CLIArgument.Positional.init));
    static assert(splitArgumentNameValue("-abc") == CLIArgument.Argument(CLIArgument.NamedShort("abc", "-abc", null)));
    static assert(splitArgumentNameValue("--abc") == CLIArgument.Argument(CLIArgument.NamedLong("abc", "--abc", null)));
    static assert(splitArgumentNameValue("-abc=fd") == CLIArgument.Argument(CLIArgument.NamedShort("abc", "-abc", "fd")));
    static assert(splitArgumentNameValue("--abc=fd") == CLIArgument.Argument(CLIArgument.NamedLong("abc", "--abc", "fd")));
    static assert(splitArgumentNameValue("-abc=") == CLIArgument.Argument(CLIArgument.NamedShort("abc", "-abc", "")));
    static assert(splitArgumentNameValue("--abc=") == CLIArgument.Argument(CLIArgument.NamedLong("abc", "--abc", "")));
    static assert(splitArgumentNameValue("-=abc") == CLIArgument.Argument(CLIArgument.NamedShort("", "-", "abc")));
    static assert(splitArgumentNameValue("--=abc") == CLIArgument.Argument(CLIArgument.NamedLong("", "--", "abc")));
}


private template defaultValuesCount(T)
if(!is(T == void))
{
    import std.traits;

    static if(isBoolean!T)
    {
        enum min = 0;
        enum max = 0;
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


private template EnumMembersAsStrings(E)
{
    enum EnumMembersAsStrings = {
        import std.traits: EnumMembers;
        alias members = EnumMembers!E;

        typeof(__traits(identifier, members[0]))[] res;
        static foreach (i, _; members)
            res ~= __traits(identifier, members[i]);

        return res;
    }();
}

unittest
{
    enum E { abc, def, ghi }
    assert(EnumMembersAsStrings!E == ["abc", "def", "ghi"]);
}

private auto setDefaults(TYPE, alias symbol)(ArgumentInfo info)
{
    static if(!isBoolean!TYPE)
        info.allowBooleanNegation = false;

    static if(is(TYPE == enum))
        info.setAllowedValues!(EnumMembersAsStrings!TYPE);

    if(info.names.length == 0)
        info.names = [ symbol ];

    if(info.minValuesCount.isNull) info.minValuesCount = defaultValuesCount!TYPE.min;
    if(info.maxValuesCount.isNull) info.maxValuesCount = defaultValuesCount!TYPE.max;

    if(info.placeholder.length == 0)
    {
        import std.uni : toUpper;
        info.placeholder = info.positional ? symbol : symbol.toUpper;
    }

    return info;
}

unittest
{
    ArgumentInfo info;
    info.allowBooleanNegation = true;
    info.position = 0;

    auto res = info.setDefaults!(int, "default-name");
    assert(!res.allowBooleanNegation);
    assert(res.names == [ "default-name" ]);
    assert(res.minValuesCount == defaultValuesCount!int.min);
    assert(res.maxValuesCount == defaultValuesCount!int.max);
    assert(res.placeholder == "default-name");

    info.placeholder = "myvalue";
    res = info.setDefaults!(int, "default-name");
    assert(res.placeholder == "myvalue");
}

unittest
{
    ArgumentInfo info;
    info.allowBooleanNegation = true;

    auto res = info.setDefaults!(bool, "default_name");
    assert(res.allowBooleanNegation);
    assert(res.names == ["default_name"]);
    assert(res.minValuesCount == defaultValuesCount!bool.min);
    assert(res.maxValuesCount == defaultValuesCount!bool.max);
    assert(res.placeholder == "DEFAULT_NAME");

    info.placeholder = "myvalue";
    res = info.setDefaults!(bool, "default_name");
    assert(res.placeholder == "myvalue");
}

unittest
{
    enum E { a=1, b=1, c }
    static assert(EnumMembersAsStrings!E == ["a","b","c"]);

    ArgumentInfo info;
    auto res = info.setDefaults!(E, "default-name");
    assert(res.placeholder == "{a,b,c}");

    info.placeholder = "myvalue";
    res = info.setDefaults!(E, "default-name");
    assert(res.placeholder == "myvalue");
}


private auto checkDuplicates(alias sortedRange, string errorMsg)() {
    static if(sortedRange.length >= 2)
    {
        enum value = {
            import std.conv : to;

            foreach(i; 1..sortedRange.length-1)
                if(sortedRange[i-1] == sortedRange[i])
                    return sortedRange[i].to!string;

            return "";
        }();
        static assert(value.length == 0, errorMsg ~ value);
    }

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

private struct Group
{
    string name;
    string description;

    private size_t[] arguments;

    auto ref Description(string text)
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


private struct RestrictionGroup
{
    string location;

    enum Type { together, exclusive }
    Type type;

    private size_t[] arguments;
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


private alias ParseFunction(RECEIVER) = bool delegate(in Config config, string argName, ref RECEIVER receiver, string[] rawValues);
private alias Restriction = bool delegate(in Config config, in bool[size_t] cliArgs);

// Have to do this magic because closures are not supported in CFTE
// DMD v2.098.0 prints "Error: closures are not yet supported in CTFE"
auto partiallyApply(alias fun,C...)(C context)
{
    import std.traits: ParameterTypeTuple;
    import core.lifetime: move, forward;

    return &new class(move(context))
    {
        C context;

        this(C ctx)
        {
            foreach(i, ref c; context)
                c = move(ctx[i]);
        }

        auto opCall(ParameterTypeTuple!fun[context.length..$] args) const
        {
            return fun(context, forward!args);
        }
    }.opCall;
}

private struct Restrictions
{
    static Restriction RequiredArg(ArgumentInfo info)(size_t index)
    {
        return partiallyApply!((size_t index, in Config config, in bool[size_t] cliArgs)
        {
            if(index in cliArgs)
                return true;

            config.onError("The following argument is required: ", info.names[0].getArgumentName(config));
            return false;
        })(index);
    }

    static bool RequiredTogether(in Config config,
                                 in bool[size_t] cliArgs,
                                 in size_t[] restrictionArgs,
                                 in ArgumentInfo[] allArgs)
    {
        size_t foundIndex = size_t.max;
        size_t missedIndex = size_t.max;

        foreach(index; restrictionArgs)
        {
            if(index in cliArgs)
            {
                if(foundIndex == size_t.max)
                    foundIndex = index;
            }
            else if(missedIndex == size_t.max)
                missedIndex = index;

            if(foundIndex != size_t.max && missedIndex != size_t.max)
            {
                config.onError("Missed argument '", allArgs[missedIndex].names[0].getArgumentName(config),
                    "' - it is required by argument '", allArgs[foundIndex].names[0].getArgumentName(config),"'");
                return false;
            }
        }

        return true;
    }

    static bool MutuallyExclusive(in Config config,
                                  in bool[size_t] cliArgs,
                                  in size_t[] restrictionArgs,
                                  in ArgumentInfo[] allArgs)
    {
        size_t foundIndex = size_t.max;

        foreach(index; restrictionArgs)
            if(index in cliArgs)
            {
                if(foundIndex == size_t.max)
                    foundIndex = index;
                else
                {
                    config.onError("Argument '", allArgs[foundIndex].names[0].getArgumentName(config),
                                   "' is not allowed with argument '", allArgs[index].names[0].getArgumentName(config),"'");
                    return false;
                }

            }

        return true;
    }
}

private struct Arguments(RECEIVER)
{
    static assert(getSymbolsByUDA!(RECEIVER, TrailingArguments).length <= 1,
                  "Type "~RECEIVER.stringof~" must have at most one 'TrailingArguments' UDA");

    private enum _validate = checkArgumentNames!RECEIVER &&
                             checkPositionalIndexes!RECEIVER;



    immutable string function(string str) convertCase;

    private ArgumentInfo[] arguments;
    private ParseFunction!RECEIVER[] parseFunctions;

    // named arguments
    private size_t[string] argsNamed;

    // positional arguments
    private size_t[] argsPositional;


    Group[] groups;
    enum requiredGroupIndex = 0;
    enum optionalGroupIndex = 1;

    size_t[string] groupsByName;

    Restriction[] restrictions;
    RestrictionGroup[] restrictionGroups;

    @property ref Group requiredGroup() { return groups[requiredGroupIndex]; }
    @property ref const(Group) requiredGroup() const { return groups[requiredGroupIndex]; }
    @property ref Group optionalGroup() { return groups[optionalGroupIndex]; }
    @property ref const(Group) optionalGroup() const { return groups[optionalGroupIndex]; }

    @property auto positionalArguments() const { return argsPositional; }


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

        groups = [ Group("Required arguments"), Group("Optional arguments") ];
    }

    private void addArgument(ArgumentInfo info, RestrictionGroup[] restrictions, Group group)(ParseFunction!RECEIVER parse)
    {
        auto index = (group.name in groupsByName);
        if(index !is null)
            addArgument!(info, restrictions)(parse, groups[*index]);
        else
        {
            groupsByName[group.name] = groups.length;
            groups ~= group;
            addArgument!(info, restrictions)(parse, groups[$-1]);
        }
    }

    private void addArgument(ArgumentInfo info, RestrictionGroup[] restrictions = [])(ParseFunction!RECEIVER parse)
    {
        static if(info.required)
            addArgument!(info, restrictions)(parse, requiredGroup);
        else
            addArgument!(info, restrictions)(parse, optionalGroup);
    }

    private void addArgument(ArgumentInfo info, RestrictionGroup[] argRestrictions = [])(ParseFunction!RECEIVER parse, ref Group group)
    {
        static assert(info.names.length > 0);

        immutable index = arguments.length;

        static if(info.positional)
        {
            if(argsPositional.length <= info.position.get)
                argsPositional.length = info.position.get + 1;

            argsPositional[info.position.get] = index;
        }
        else
            static foreach(name; info.names)
            {
                assert(!(name in argsNamed), "Duplicated argument name: "~name);
                argsNamed[convertCase(name)] = index;
            }

        arguments ~= info;
        parseFunctions ~= parse;
        group.arguments ~= index;

        static if(info.required)
            restrictions ~= Restrictions.RequiredArg!info(index);

        static foreach(restriction; argRestrictions)
            addRestriction!(info, restriction)(index);
    }

    private void addRestriction(ArgumentInfo info, RestrictionGroup restriction)(size_t argIndex)
    {
        auto groupIndex = (restriction.location in groupsByName);
        auto index = groupIndex !is null
            ? *groupIndex
            : {
                auto index = groupsByName[restriction.location] = restrictionGroups.length;
                restrictionGroups ~= restriction;
                return index;
            }();

        restrictionGroups[index].arguments ~= argIndex;
    }


    private bool checkRestrictions(in bool[size_t] cliArgs, in Config config) const
    {
        foreach(restriction; restrictions)
            if(!restriction(config, cliArgs))
                return false;

        foreach(restriction; restrictionGroups)
            final switch(restriction.type)
            {
                case RestrictionGroup.Type.together:
                    if(!Restrictions.RequiredTogether(config, cliArgs, restriction.arguments, arguments))
                        return false;
                    break;
                case RestrictionGroup.Type.exclusive:
                    if(!Restrictions.MutuallyExclusive(config, cliArgs, restriction.arguments, arguments))
                        return false;
                    break;
            }

        return true;
    }


    private auto findArgumentImpl(const size_t* pIndex) const
    {
        import std.typecons : Tuple;

        alias Result = Tuple!(size_t, "index", const(ArgumentInfo)*, "arg", ParseFunction!RECEIVER, "parse");

        return pIndex ? Result(*pIndex, &arguments[*pIndex], parseFunctions[*pIndex]) : Result(size_t.max, null, null);
    }

    auto findPositionalArgument(size_t position) const
    {
        return findArgumentImpl(position < argsPositional.length ? &argsPositional[position] : null);
    }

    auto findNamedArgument(string name) const
    {
        return findArgumentImpl(convertCase(name) in argsNamed);
    }

    static if(getSymbolsByUDA!(RECEIVER, TrailingArguments).length == 1)
    {
        private void setTrailingArgs(ref RECEIVER receiver, string[] rawValues) const
        {
            enum symbol = __traits(identifier, getSymbolsByUDA!(RECEIVER, TrailingArguments)[0]);
            auto target = &__traits(getMember, receiver, symbol);

            static if(__traits(compiles, { *target = rawValues; }))
                *target = rawValues;
            else
                static assert(false, "Type '"~typeof(*target).stringof~"' of `"~
                    RECEIVER.stringof~"."~symbol~"` is not supported for 'TrailingArguments' UDA");
        }
    }
}

private alias ParsingFunction(alias symbol, alias uda, ArgumentInfo info, RECEIVER) =
    delegate(in Config config, string argName, ref RECEIVER receiver, string[] rawValues)
    {
        try
        {
            if(!info.checkValuesCount(config, argName, rawValues.length))
                return false;

            auto param = RawParam(config, argName, rawValues);

            auto target = &__traits(getMember, receiver, symbol);

            static if(is(typeof(target) == function) || is(typeof(target) == delegate))
                return uda.parsingFunc.parse(target, param);
            else
                return uda.parsingFunc.parse(*target, param);
        }
        catch(Exception e)
        {
            config.onError(argName, ": ", e.msg);
            return false;
        }
    };


private void addArgument(alias symbol, RECEIVER)(ref Arguments!RECEIVER args)
{
    alias member = __traits(getMember, RECEIVER, symbol);

    static assert(getUDAs!(member, ArgumentUDA).length <= 1,
        "Member "~RECEIVER.stringof~"."~symbol~" has multiple '*Argument' UDAs");

    static assert(getUDAs!(member, Group).length <= 1,
        "Member "~RECEIVER.stringof~"."~symbol~" has multiple 'Group' UDAs");

    static if(getUDAs!(member, ArgumentUDA).length > 0)
        enum uda = getUDAs!(member, ArgumentUDA)[0];
    else
        enum uda = NamedArgument();

    enum info = uda.info.setDefaults!(typeof(member), symbol);

    enum restrictions = {
        RestrictionGroup[] restrictions;
        static foreach(gr; getUDAs!(member, RestrictionGroup))
            restrictions ~= gr;
        return restrictions;
    }();

    static if(getUDAs!(member, Group).length > 0)
        args.addArgument!(info, restrictions, getUDAs!(member, Group)[0])(ParsingFunction!(symbol, uda, info, RECEIVER));
    else
        args.addArgument!(info, restrictions)(ParsingFunction!(symbol, uda, info, RECEIVER));
}

private auto createArguments(RECEIVER)(bool caseSensitive)
{
    auto args = Arguments!RECEIVER(caseSensitive);

    enum hasNoUDAs = getSymbolsByUDA!(RECEIVER, ArgumentUDA  ).length == 0 &&
                     getSymbolsByUDA!(RECEIVER, NamedArgument).length == 0;

    static foreach(sym; __traits(allMembers, RECEIVER))
    {{
        alias mem = __traits(getMember,RECEIVER,sym);

        static if(!is(mem)) // skip types
            static if(hasNoUDAs || hasUDA!(mem, ArgumentUDA) || hasUDA!(mem, NamedArgument))
                addArgument!(sym)(args);
    }}

    return args;
}

unittest
{
    struct T
    {
        @(NamedArgument)
        int a;
        @(NamedArgument.Optional())
        int b;
        @(NamedArgument.Required())
        int c;
        @(NamedArgument)
        int d;
        @(NamedArgument.Required())
        int e;
        @(NamedArgument)
        int f;
    }
    static assert(createArguments!T(true).arguments.length == 6);

    auto a = createArguments!T(true);
    assert(a.requiredGroup.arguments == [2,4]);
    assert(a.argsNamed == ["a":0LU, "b":1LU, "c":2LU, "d":3LU, "e":4LU, "f":5LU]);
    assert(a.argsPositional == []);
}

unittest
{
    struct T
    {
        int a,b,c,d,e,f;
    }
    static assert(createArguments!T(true).arguments.length == 6);

    auto a = createArguments!T(true);
    assert(a.requiredGroup.arguments == []);
    assert(a.argsNamed == ["a":0LU, "b":1LU, "c":2LU, "d":3LU, "e":4LU, "f":5LU]);
    assert(a.argsPositional == []);
}

unittest
{
    struct T1
    {
        @(NamedArgument("1"))
        @(NamedArgument("2"))
        int a;
    }
    static assert(!__traits(compiles, { createArguments!T1(true); }));

    struct T2
    {
        @(NamedArgument("1"))
        int a;
        @(NamedArgument("1"))
        int b;
    }
    static assert(!__traits(compiles, { createArguments!T1(true); }));

    struct T3
    {
        @(PositionalArgument(0)) int a;
        @(PositionalArgument(0)) int b;
    }
    static assert(!__traits(compiles, { createArguments!T3(true); }));

    struct T4
    {
        @(PositionalArgument(0)) int a;
        @(PositionalArgument(2)) int b;
    }
    static assert(!__traits(compiles, { createArguments!T4(true); }));
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


private enum helpArgument = {
    ArgumentInfo arg;
    arg.names = ["h","help"];
    arg.description = "Show this help message and exit";
    arg.minValuesCount = 0;
    arg.maxValuesCount = 0;
    arg.allowBooleanNegation = false;
    arg.parsingTerminateCode = 0;
    return arg;
}();

struct ParseCLIResult
{
    int  resultCode;

    private bool done;

    bool opCast(type)() if (is(type == bool))
    {
        return done;
    }

    private static enum failure = ParseCLIResult(1);
    private static enum success = ParseCLIResult(0, true);
}

private ParseCLIResult parseCLIKnownArgs(T)(ref T receiver,
                                            string[] args,
                                            out string[] unrecognizedArgs,
                                            const ref CommandArguments!T command,
                                            in Config config)
{
    import std.algorithm: map;
    import std.array: assocArray;
    import std.range: repeat, empty, front, popFront, join;
    import std.typecons : tuple;
    import std.sumtype : match;

    checkArgumentName!T(config.namedArgChar);

    bool[size_t] cliArgs;

    size_t positionalArgIdx = 0;

    alias parseArgument = (string value, nameWithDash, foundArg) {
        auto values = value is null ? consumeValuesFromCLI(args, *foundArg.arg, config) : [ value ];

        if(!foundArg.parse(config, nameWithDash, receiver, values))
            return ParseCLIResult.failure;

        if(!foundArg.arg.parsingTerminateCode.isNull)
            return ParseCLIResult(foundArg.arg.parsingTerminateCode.get);

        cliArgs[foundArg.index] = true;

        return ParseCLIResult.success;
    };

    auto unknownArg(CLIArgument.Unknown = CLIArgument.Unknown.init) {
        unrecognizedArgs ~= args.front;
        args.popFront();
        return ParseCLIResult.success;
    }

    auto positionalArg(CLIArgument.Positional) {
        auto foundArg = command.arguments.findPositionalArgument(positionalArgIdx);
        if(foundArg.arg is null)
            return unknownArg();

        auto res = parseArgument(null, foundArg.arg.names[0], foundArg);
        if(res == ParseCLIResult.success)
            positionalArgIdx++;

        return res;
    }

    alias namedLongArg = (CLIArgument.NamedLong arg) {
        import std.algorithm : startsWith;

        auto foundArg = command.arguments.findNamedArgument(arg.name);

        if(foundArg.arg is null && arg.name.startsWith("no-"))
        {
            foundArg = command.arguments.findNamedArgument(arg.name[3..$]);
            if(foundArg.arg is null || !foundArg.arg.allowBooleanNegation)
                return unknownArg();

            arg.value = "false";
        }

        if(foundArg.arg is null)
            return unknownArg();

        args.popFront();
        return parseArgument(arg.value, arg.nameWithDash, foundArg);
    };

    alias namedShortArg = (CLIArgument.NamedShort arg) {
        auto foundArg = command.arguments.findNamedArgument(arg.name);
        if(foundArg.arg !is null)
        {
            args.popFront();
            return parseArgument(arg.value, arg.nameWithDash, foundArg);
        }

        // Try to parse "-ABC..." where "A","B","B" are different single-letter arguments
        do
        {
            auto name = [arg.name[0]];
            foundArg = command.arguments.findNamedArgument(name);
            if(foundArg.arg is null)
                return unknownArg();

            // In case of bundling there can be no or one argument value
            if(config.bundling && foundArg.arg.minValuesCount.get > 1)
                return unknownArg();

            // In case of NO bundling there MUST be one argument value
            if(!config.bundling && foundArg.arg.minValuesCount.get != 1)
                return unknownArg();

            string value;
            if(foundArg.arg.minValuesCount == 0)
                arg.name = arg.name[1..$];
            else
            {
                // Bundling case: try to parse "-ABvalue" where "A","B" are different single-letter arguments and "value" is a value for "B"
                // No bundling case: try to parse "-Avalue" where "A" is a single-letter argument and "value" is its value
                value = arg.name[1..$];
                arg.name = "";
            }

            auto res = parseArgument(value, "-"~name, foundArg);
            if(res != ParseCLIResult.success)
                return res;
        }
        while(arg.name.length > 0);

        args.popFront();
        return ParseCLIResult.success;
    };

    while(!args.empty)
    {
        if(config.endOfArgs.length > 0 && args.front == config.endOfArgs)
        {
            // End of arguments
            static if(is(typeof(command.arguments.setTrailingArgs)))
                command.arguments.setTrailingArgs(receiver, args[1..$]);
            else
                unrecognizedArgs ~= args[1..$];
            break;
        }

        immutable res = splitArgumentNameValue(args.front, config).match!(
            unknownArg,
            positionalArg,
            namedLongArg,
            namedShortArg
        );
        if(res != ParseCLIResult.success)
            return res;
    }

    if(!command.arguments.checkRestrictions(cliArgs, config))
        return ParseCLIResult.failure;

    return ParseCLIResult.success;
}

ParseCLIResult parseCLIKnownArgs(T)(ref T receiver,
                                    string[] args,
                                    out string[] unrecognizedArgs,
                                    in Config config = Config.init)
{
    auto command = CommandArguments!T(config);
    return parseCLIKnownArgs(receiver, args, unrecognizedArgs, command, config);
}

auto parseCLIKnownArgs(T)(ref T receiver, ref string[] args, in Config config = Config.init)
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
        return res.resultCode;

    static if(__traits(compiles, { int a = cast(int) func(value, args); }))
        return cast(int) func(value, args);
    else
    {
        func(value, args);
        return 0;
    }
}


auto parseCLIArgs(T)(ref T receiver, string[] args, in Config config = Config.init)
{
    string[] unrecognizedArgs;

    auto res = parseCLIKnownArgs(receiver, args, unrecognizedArgs, config);

    if(res && unrecognizedArgs.length > 0)
    {
        config.onError("Unrecognized arguments: ", unrecognizedArgs);
        return ParseCLIResult.failure;
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
    static assert(p.arguments.findNamedArgument("a").arg is null);
    static assert(p.arguments.findNamedArgument("b").arg !is null);
    static assert(p.arguments.findNamedArgument("boo").arg !is null);
    static assert(p.arguments.findPositionalArgument(0).arg !is null);
    static assert(p.arguments.findPositionalArgument(1).arg is null);
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

    static assert(["-b"]        .parseCLIArgs!T.get == T(true));
    static assert(["-b=true"]   .parseCLIArgs!T.get == T(true));
    static assert(["-b=false"]  .parseCLIArgs!T.get == T(false));
    assert(["-b"]        .parseCLIArgs!T.get == T(true));
    assert(["-b=true"]   .parseCLIArgs!T.get == T(true));
    assert(["-b=false"]  .parseCLIArgs!T.get == T(false));
}

struct Main
{
    mixin template parseCLIKnownArgs(TYPE, alias newMain, Config config = Config.init)
    {
        int main(string[] argv)
        {
            return parseCLIKnownArgs!TYPE(argv[1..$], (TYPE values, string[] args) => newMain(values, args), config);
        }
    }

    mixin template parseCLIArgs(TYPE, alias newMain, Config config = Config.init)
    {
        int main(string[] argv)
        {
            return parseCLIArgs!TYPE(argv[1..$], (TYPE values) => newMain(values), config);
        }
    }
}

unittest
{
    struct T
    {
        int a;
    }

    static assert(__traits(compiles, { mixin Main.parseCLIArgs!(T, (params) => 0); }));
    static assert(__traits(compiles, { mixin Main.parseCLIKnownArgs!(T, (params, args) => 0); }));
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


private struct Validators
{
    static auto ValueInList(alias values, TYPE)(in Param!TYPE param)
    {
        import std.array : assocArray, join;
        import std.range : repeat, front;
        import std.conv: to;

        enum valuesAA = assocArray(values, false.repeat);
        enum allowedValues = values.to!(string[]).join(',');

        static if(is(typeof(values.front) == TYPE))
            auto paramValues = [param.value];
        else
            auto paramValues = param.value;

        foreach(value; paramValues)
            if(!(value in valuesAA))
            {
                param.config.onError("Invalid value '", value, "' for argument '", param.name, "'.\nValid argument values are: ", allowedValues);
                return false;
            }

        return true;
    }
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
            static assert(false, funcName~" function is not supported for type "~T.stringof~": "~typeof(F).stringof);
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

    static if(is(T == enum))
    {
        alias DefaultValueParseFunctions = ValueParseFunctions!(
        void,   // pre process
        Validators.ValueInList!(EnumMembersAsStrings!T, typeof(RawParam.value)),   // pre validate
        void,   // parse
        void,   // validate
        void,   // action
        void    // no-value action
        );
    }
    else static if(isSomeString!T || isNumeric!T)
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

    string description;
    string placeholder;

    private void setAllowedValues(alias names)()
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

    Nullable!int parsingTerminateCode;
}



////////////////////////////////////////////////////////////////////////////////////////////////////
// User defined attributes
////////////////////////////////////////////////////////////////////////////////////////////////////
private struct ArgumentUDA(alias ValueParseFunctions)
{
    ArgumentInfo info;

    alias parsingFunc = ValueParseFunctions;



    auto ref Description(string text)
    {
        info.description = text;
        return this;
    }

    auto ref HideFromHelp(bool hide = true)
    {
        info.hideFromHelp = hide;
        return this;
    }

    auto ref Placeholder(string value)
    {
        info.placeholder = value;
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

    auto ref NumberOfValues(ulong num)
    {
        info.minValuesCount = num;
        info.maxValuesCount = num;
        return this;
    }

    auto ref NumberOfValues(ulong min, ulong max)
    {
        info.minValuesCount = min;
        info.maxValuesCount = max;
        return this;
    }

    auto ref MinNumberOfValues(ulong min)
    {
        assert(min <= info.maxValuesCount.get(ulong.max));

        info.minValuesCount = min;
        return this;
    }

    auto ref MaxNumberOfValues(ulong max)
    {
        assert(max >= info.minValuesCount.get(0));

        info.maxValuesCount = max;
        return this;
    }

    // ReverseSwitch
}

unittest
{
    auto arg = NamedArgument.Description("desc").Placeholder("text");
    assert(arg.info.description == "desc");
    assert(arg.info.placeholder == "text");
    assert(!arg.info.hideFromHelp);
    assert(!arg.info.required);
    assert(arg.info.minValuesCount.isNull);
    assert(arg.info.maxValuesCount.isNull);

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

unittest
{
    struct T
    {
        @(NamedArgument.NumberOfValues(1,3))
        int[] a;
        @(NamedArgument.NumberOfValues(2))
        int[] b;
    }

    assert(["-a","1","2","3","-b","4","5"].parseCLIArgs!T.get == T([1,2,3],[4,5]));
    assert(["-a","1","-b","4","5"].parseCLIArgs!T.get == T([1],[4,5]));
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
        @(NamedArgument.Counter()) int a;
    }

    static assert(["-a","-a","-a"].parseCLIArgs!T.get == T(3));
    assert(["-a","-a","-a"].parseCLIArgs!T.get == T(3));
}


auto AllowedValues(alias values, ARG)(ARG arg)
{
    import std.array : assocArray;
    import std.range : repeat;

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


unittest
{
    struct T
    {
        string a;
        string b;

        @TrailingArguments string[] args;
    }

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

    static assert(["-i","-5","-u","8","-d","12.345"].parseCLIArgs!T.get == T(-5,8,12.345));
    static assert(["-i","-5","-u1","8","-d1","12.345"].parseCLIArgs!T.get == T(-5,8,12.345));
    assert(["-i","-5","-u","8","-d","12.345"].parseCLIArgs!T.get == T(-5,8,12.345));
    assert(["-i","-5","-u1","8","-d1","12.345"].parseCLIArgs!T.get == T(-5,8,12.345));
}

unittest
{
    struct T
    {
        @(NamedArgument) int[]   a;
        @(NamedArgument) int[][] b;
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
        @NamedArgument int[] a;
    }

    Config cfg;
    cfg.arraySep = ',';

    assert(["-a","1,2,3","-a","4","5"].parseCLIArgs!T(cfg).get == T([1,2,3,4,5]));
}

unittest
{
    struct T
    {
        @NamedArgument int[string] a;
    }

    static assert(["-a=foo=3","-a","boo=7"].parseCLIArgs!T.get.a == ["foo":3,"boo":7]);
    assert(["-a=foo=3","-a","boo=7"].parseCLIArgs!T.get.a == ["foo":3,"boo":7]);
}

unittest
{
    struct T
    {
        @NamedArgument int[string] a;
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

        @NamedArgument Fruit a;
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
        @NamedArgument string[] a;
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
        @(NamedArgument.AllowNoValue  !10) int a;
        @(NamedArgument.RequireNoValue!20) int b;
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
        @(NamedArgument
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


//private
string getProgramName()
{
    import core.runtime: Runtime;
    import std.path: baseName;
    return Runtime.args[0].baseName;
}

unittest
{
    assert(getProgramName().length > 0);
}


private struct CommandInfo
{
    private string name;
    private string usage;
    private string description;
    private string epilog;

    auto ref Usage(string text)
    {
        usage = text;
        return this;
    }

    auto ref Description(string text)
    {
        description = text;
        return this;
    }

    auto ref Epilog(string text)
    {
        epilog = text;
        return this;
    }
}

auto Command(string name = "")
{
    return CommandInfo(name);
}

unittest
{
    assert(Command("MYPROG").name == "MYPROG");
}


private struct CommandArguments(RECEIVER)
{
    static assert(getUDAs!(RECEIVER, CommandInfo).length <= 1);

    static if(getUDAs!(RECEIVER, CommandInfo).length == 0)
        CommandInfo info;
    else
        CommandInfo info = getUDAs!(RECEIVER, CommandInfo)[0];

    Arguments!RECEIVER arguments;


    private this(in Config config)
    {
        arguments = createArguments!RECEIVER(config.caseSensitive);

        if(config.addHelp)
        {
            arguments.addArgument!helpArgument(delegate (in Config config, string argName, ref RECEIVER receiver, string[] rawValues)
            {
                import std.stdio: stdout;

                printHelp(stdout.lockingTextWriter(), this, config);

                return true;
            });
        }
    }
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// Help-printing functions
////////////////////////////////////////////////////////////////////////////////////////////////////
private void printValue(Output)(auto ref Output output, in ArgumentInfo info)
{
    if(info.maxValuesCount.get == 0)
        return;

    if(info.minValuesCount.get == 0)
        output.put('[');

    output.put(info.placeholder);
    if(info.maxValuesCount.get > 1)
        output.put(" ...");

    if(info.minValuesCount.get == 0)
        output.put(']');
}

unittest
{
    auto test(int min, int max)
    {
        ArgumentInfo info;
        info.placeholder = "v";
        info.minValuesCount = min;
        info.maxValuesCount = max;

        import std.array: appender;
        auto a = appender!string;
        a.printValue(info);
        return a[];
    }

    assert(test(0,0) == "");
    assert(test(0,1) == "[v]");
    assert(test(0,5) == "[v ...]");
    assert(test(1,1) == "v");
    assert(test(1,5) == "v ...");
    assert(test(3,3) == "v ...");
    assert(test(3,5) == "v ...");
}


private string getArgumentName(string name, in Config config)
{
    name = config.namedArgChar ~ name;
    return name.length > 2 ? config.namedArgChar ~ name : name;
}

unittest
{
    assert(getArgumentName("f", Config.init) == "-f");
    assert(getArgumentName("foo", Config.init) == "--foo");
}


private void printInvocation(Output)(auto ref Output output, in ArgumentInfo info, in string[] names, in Config config)
{
    if(info.positional)
        output.printValue(info);
    else
    {
        import std.algorithm: each;

        names.each!((i, name)
        {
            if(i > 0)
                output.put(", ");

            output.put(getArgumentName(name, config));

            if(info.maxValuesCount.get > 0)
            {
                output.put(' ');
                output.printValue(info);
            }
        });
    }
}

unittest
{
    auto test(bool positional)
    {
        ArgumentInfo info;
        info.placeholder = "v";
        if(positional)
            info.position = 0;

        import std.array: appender;
        auto a = appender!string;
        a.printInvocation(info.setDefaults!(int, "foo"), ["f","foo"], Config.init);
        return a[];
    }

    assert(test(false) == "-f v, --foo v");
    assert(test(true) == "v");
}


private void printUsage(Output)(auto ref Output output, in ArgumentInfo info, in Config config)
{
    if(!info.required)
        output.put('[');

    output.printInvocation(info, [info.names[0]], config);

    if(!info.required)
        output.put(']');
}

unittest
{
    auto test(bool required, bool positional)
    {
        ArgumentInfo info;
        info.names ~= "foo";
        info.placeholder = "v";
        info.required = required;
        if(positional)
            info.position = 0;

        import std.array: appender;
        auto a = appender!string;
        a.printUsage(info.setDefaults!(int, "foo"), Config.init);
        return a[];
    }

    assert(test(false, false) == "[--foo v]");
    assert(test(false, true) == "[v]");
    assert(test(true, false) == "--foo v");
    assert(test(true, true) == "v");
}


private void substituteProg(Output)(auto ref Output output, string text, string prog)
{
    import std.array: replaceInto;
    output.replaceInto(text, "%(PROG)", prog);
}

unittest
{
    import std.array: appender;
    auto a = appender!string;
    a.substituteProg("this is some text where %(PROG) is substituted but PROG and prog are not", "-myprog-");
    assert(a[] == "this is some text where -myprog- is substituted but PROG and prog are not");
}


private string spaces(ulong num)
{
    import std.range: repeat;
    import std.array: array;
    return ' '.repeat(num).array;
}

unittest
{
    assert(spaces(0) == "");
    assert(spaces(1) == " ");
    assert(spaces(5) == "     ");
}

private void printUsage(T, Output)(auto ref Output output, in CommandArguments!T cmd, in Config config)
{
    output.put("usage: ");

    if(cmd.info.usage.length > 0)
        substituteProg(output, cmd.info.usage, cmd.info.name);
    else
    {
        import std.algorithm: filter, each, map;

        alias print = (r) => r
            .filter!((ref _) => !_.hideFromHelp)
            .each!((ref _)
            {
                output.put(' ');
                output.printUsage(_, config);
            });

        output.put(cmd.info.name.length > 0 ? cmd.info.name : getProgramName());

        // named args
        print(cmd.arguments.arguments.filter!((ref _) => !_.positional));
        // positional args
        print(cmd.arguments.positionalArguments.map!(ref (_) => cmd.arguments.arguments[_]));

        output.put('\n');
    }
}

void printUsage(T, Output)(auto ref Output output, in Config config)
{
    printUsage(output, CommandArguments!T(config), config);
}

unittest
{
    @(Command("MYPROG").Usage("custom usage of %(PROG)"))
    struct T
    {
        string s;
    }

    auto test(string usage)
    {
        import std.array: appender;

        auto a = appender!string;
        a.printUsage!T(Config.init);
        return a[];
    }

    enum expected = "usage: custom usage of MYPROG";
    static assert(test("custom usage of %(PROG)") == expected);
    assert(test("custom usage of %(PROG)") == expected);
}


private void printHelp(Output, ARGS)(auto ref Output output, in Group group, ARGS args, int helpPosition)
{
    import std.string: leftJustify;

    if(group.arguments.length == 0 || group.name.length == 0)
        return;

    output.put(group.name);
    output.put(":\n");

    if(group.description.length > 0)
    {
        output.put("  ");
        output.put(group.description);
        output.put("\n\n");
    }

    immutable ident = spaces(helpPosition + 2);

    foreach(idx; group.arguments)
    {
        auto arg = &args[idx];

        if(arg.invocation.length == 0)
            continue;
        else if(arg.invocation.length <= helpPosition - 4) // 2=indent, 2=two spaces between invocation and help text
        {
            import std.array: appender;

            auto invocation = appender!string;
            invocation ~= "  ";
            invocation ~= arg.invocation.leftJustify(helpPosition);
            output.wrapMutiLine(arg.help, 80-2, invocation[], ident);
        }
        else
        {
            // long action name; start on the next line
            output.put("  ");
            output.put(arg.invocation);
            output.put("\n");
            output.wrapMutiLine(arg.help, 80-2, ident, ident);
        }
    }

    output.put('\n');
}


private void printHelp(T, Output)(auto ref Output output, in CommandArguments!T cmd, in Config config)
{
    import std.algorithm: map, maxElement, min;
    import std.array: appender, array;

    printUsage(output, cmd, config);
    output.put('\n');

    if(cmd.info.description.length > 0)
    {
        output.put(cmd.info.description);
        output.put("\n\n");
    }

    // pre-compute the output
    auto args =
        cmd.arguments.arguments
        .map!((ref _)
        {
            import std.typecons : tuple;

            if(_.hideFromHelp)
                return tuple!("invocation","help")("", "");

            auto invocation = appender!string;
            invocation.printInvocation(_, _.names, config);

            return tuple!("invocation","help")(invocation[], _.description);
        }).array;

    immutable maxInvocationWidth = args.map!(_ => _.invocation.length).maxElement;
    immutable helpPosition = min(maxInvocationWidth + 4, 24);

    //user-defined groups
    foreach(ref group; cmd.arguments.groups[2..$])
        output.printHelp(group, args, helpPosition);

    //required args
    output.printHelp(cmd.arguments.requiredGroup, args, helpPosition);

    //optionals args
    output.printHelp(cmd.arguments.optionalGroup, args, helpPosition);

    if(cmd.info.epilog.length > 0)
    {
        output.put(cmd.info.epilog);
        output.put('\n');
    }
}

void printHelp(T, Output)(auto ref Output output, in Config config)
{
    printHelp(output, CommandArguments!T(config), config);
}

unittest
{
    @(Command("MYPROG")
     .Description("custom description")
     .Epilog("custom epilog")
    )
    struct T
    {
        @NamedArgument  string s;
        @(NamedArgument.Placeholder("VALUE"))  string p;

        @(NamedArgument.HideFromHelp())  string hidden;

        enum Fruit { apple, pear };
        @(NamedArgument(["f","fruit"]).Required().Description("This is a help text for fruit. Very very very very very very very very very very very very very very very very very very very long text")) Fruit f;

        @(NamedArgument.AllowedValues!([1,4,16,8])) int i;

        @(PositionalArgument(0).Description("This is a help text for param0. Very very very very very very very very very very very very very very very very very very very long text")) string param0;
        @(PositionalArgument(1).AllowedValues!(["q","a"])) string param1;

        @TrailingArguments string[] args;
    }

    auto test(alias func)()
    {
        import std.array: appender;

        auto a = appender!string;
        func!T(a, Config.init);
        return a[];
    }
    static assert(test!printUsage.length > 0);  // ensure that it works at compile time
    static assert(test!printHelp .length > 0);  // ensure that it works at compile time

    assert(test!printUsage == "usage: MYPROG [-s S] [-p VALUE] -f {apple,pear} [-i {1,4,16,8}] [-h] param0 {q,a}\n");
    assert(test!printHelp  == "usage: MYPROG [-s S] [-p VALUE] -f {apple,pear} [-i {1,4,16,8}] [-h] param0 {q,a}\n\n"~
        "custom description\n\n"~
        "Required arguments:\n"~
        "  -f {apple,pear}, --fruit {apple,pear}\n"~
        "                          This is a help text for fruit. Very very very very\n"~
        "                          very very very very very very very very very very\n"~
        "                          very very very very very long text\n"~
        "  param0                  This is a help text for param0. Very very very very\n"~
        "                          very very very very very very very very very very\n"~
        "                          very very very very very long text\n"~
        "  {q,a}                   \n\n"~
        "Optional arguments:\n"~
        "  -s S                    \n"~
        "  -p VALUE                \n"~
        "  -i {1,4,16,8}           \n"~
        "  -h, --help              Show this help message and exit\n\n"~
        "custom epilog\n");
}

unittest
{
    @Command("MYPROG")
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

    auto test(alias func)()
    {
        import std.array: appender;

        auto a = appender!string;
        func!T(a, Config.init);
        return a[];
    }

    assert(test!printHelp  == "usage: MYPROG [-a A] [-b B] [-c C] [-d D] [-h] p q\n\n"~
        "group1:\n"~
        "  group1 description\n\n"~
        "  -a A          \n"~
        "  -b B          \n"~
        "  p             \n\n"~
        "group2:\n"~
        "  group2 description\n\n"~
        "  -c C          \n"~
        "  -d D          \n\n"~
        "Required arguments:\n"~
        "  q             \n\n"~
        "Optional arguments:\n"~
        "  -h, --help    Show this help message and exit\n\n");
}

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
        @RequiredTogether()
        {
            string a;
            string b;
        }
    }
    assert(parseCLIArgs!T(["-a","a","-b","b"], (T t) {}) == 0);
    assert(parseCLIArgs!T(["-a","a"], (T t) { assert(false); }) != 0);
    assert(parseCLIArgs!T(["-b","b"], (T t) { assert(false); }) != 0);
    assert(parseCLIArgs!T([], (T t) {}) == 0);
}


private void wrapMutiLine(Output, S)(auto ref Output output,
                                     S s,
                                     in size_t columns = 80,
                                     S firstindent = null,
                                     S indent = null,
                                     in size_t tabsize = 8)
if (isSomeString!S)
{
    import std.string: wrap, lineSplitter, join;
    import std.algorithm: map, copy;

    auto lines = s.lineSplitter;
    if(lines.empty)
    {
        output.put(firstindent);
        output.put("\n");
        return;
    }

    output.put(lines.front.wrap(columns, firstindent, indent, tabsize));
    lines.popFront;

    lines.map!(s => s.wrap(columns, indent, indent, tabsize)).copy(output);
}

unittest
{
    string test(string s, size_t columns, string firstindent = null, string indent = null)
    {
        import std.array: appender;
        auto a = appender!string;
        a.wrapMutiLine(s, columns, firstindent, indent);
        return a[];
    }
    assert(test("a short string", 7) == "a short\nstring\n");
    assert(test("a\nshort string", 7) == "a\nshort\nstring\n");

    // wrap will not break inside of a word, but at the next space
    assert(test("a short string", 4) == "a\nshort\nstring\n");

    assert(test("a short string", 7, "\t") == "\ta\nshort\nstring\n");
    assert(test("a short string", 7, "\t", "    ") == "\ta\n    short\n    string\n");
}