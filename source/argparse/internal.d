module argparse.internal;

import argparse;
import argparse.help;
import argparse.parser;

import std.traits;
import std.sumtype: SumType, match;


package enum DEFAULT_COMMAND = "";


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/// Internal API
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package struct LazyString
{
    SumType!(string, string delegate()) value;

    this(string s) { value = s; }
    this(string delegate() dg) { value = dg; }

    void opAssign(string s) { value = s; }
    void opAssign(string delegate() dg) { value = dg; }

    @property string get() const
    {
        return value.match!(
            (string _) => _,
            (dg) => dg()
        );
    }
}

unittest
{
    LazyString s;
    s = "asd";
    assert(s.get == "asd");
    s = () => "qwe";
    assert(s.get == "qwe");
    assert(LazyString("asd").get == "asd");
    assert(LazyString(() => "asd").get == "asd");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package string getArgumentName(string name, Config* config)
{
    import std.conv: text;

    return name.length == 1 ?
        text(config.namedArgChar, name) :
        text(config.namedArgChar, config.namedArgChar, name);
}

package string getArgumentName(in ArgumentInfo info, Config* config)
{
    return info.positional ? info.placeholder : info.names[0].getArgumentName(config);
}

unittest
{
    Config config;

    auto info = ArgumentInfo(["f","b"]);
    info.position = 0;
    info.placeholder = "FF";
    assert(getArgumentName(info, &config) == "FF");

    assert(ArgumentInfo(["f","b"]).getArgumentName(&config) == "-f");
    assert(ArgumentInfo(["foo","boo"]).getArgumentName(&config) == "--foo");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Have to do this magic because closures are not supported in CFTE
// DMD v2.098.0 prints "Error: closures are not yet supported in CTFE"
package auto partiallyApply(alias fun,C...)(C context)
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

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package mixin template ForwardMemberFunction(string dest)
{
    import std.array: split;
    mixin("auto "~dest.split('.')[$-1]~"(Args...)(auto ref Args args) inout { import core.lifetime: forward; return "~dest~"(forward!args); }");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package auto consumeValuesFromCLI(ref string[] args, ulong minValuesCount, ulong maxValuesCount, char namedArgChar)
{
    import std.range: empty, front, popFront;

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
    (args.front.length == 0 || args.front[0] != namedArgChar))
    {
        values ~= args.front;
        args.popFront();
    }

    return values;
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package template EnumMembersAsStrings(E)
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

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package alias Restriction = Result delegate(Config* config, in bool[size_t] cliArgs, in ArgumentInfo[] allArgs);

package struct Restrictions
{
    static Restriction RequiredArg(ArgumentInfo info)(size_t index)
    {
        return partiallyApply!((size_t index, Config* config, in bool[size_t] cliArgs, in ArgumentInfo[] allArgs)
        {
            return (index in cliArgs) ?
                Result.Success :
                Result.Error("The following argument is required: ", info.getArgumentName(config));
        })(index);
    }

    static Result RequiredTogether(Config* config,
                                   in bool[size_t] cliArgs,
                                   in ArgumentInfo[] allArgs,
                                   in size_t[] restrictionArgs)
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
                return Result.Error("Missed argument '", allArgs[missedIndex].getArgumentName(config),
                                    "' - it is required by argument '", allArgs[foundIndex].getArgumentName(config),"'");
        }

        return Result.Success;
    }

    static Result MutuallyExclusive(Config* config,
                                    in bool[size_t] cliArgs,
                                    in ArgumentInfo[] allArgs,
                                    in size_t[] restrictionArgs)
    {
        size_t foundIndex = size_t.max;

        foreach(index; restrictionArgs)
            if(index in cliArgs)
            {
                if(foundIndex == size_t.max)
                    foundIndex = index;
                else
                    return Result.Error("Argument '", allArgs[foundIndex].getArgumentName(config),
                                        "' is not allowed with argument '", allArgs[index].getArgumentName(config),"'");
            }

        return Result.Success;
    }

    static Result RequiredAnyOf(Config* config,
                                in bool[size_t] cliArgs,
                                in ArgumentInfo[] allArgs,
                                in size_t[] restrictionArgs)
    {
        import std.algorithm: map;
        import std.array: join;

        foreach(index; restrictionArgs)
            if(index in cliArgs)
                return Result.Success;

        return Result.Error("One of the following arguments is required: '", restrictionArgs.map!(_ => allArgs[_].getArgumentName(config)).join("', '"), "'");
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package struct Arguments
{
    immutable string function(string str) convertCase;

    ArgumentInfo[] arguments;

    // named arguments
    size_t[string] argsNamed;

    // positional arguments
    size_t[] argsPositional;

    const Arguments* parentArguments;

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


    this(bool caseSensitive, const Arguments* parentArguments = null)
    {
        if(caseSensitive)
            convertCase = s => s;
        else
            convertCase = (string str)
            {
                import std.uni : toUpper;
                return str.toUpper;
            };

        this.parentArguments = parentArguments;

        groups = [ Group("Required arguments"), Group("Optional arguments") ];
    }

    void addArgument(ArgumentInfo info, RestrictionGroup[] restrictions, Group group)()
    {
        auto index = (group.name in groupsByName);
        if(index !is null)
            addArgument!(info, restrictions)(groups[*index]);
        else
        {
            groupsByName[group.name] = groups.length;
            groups ~= group;
            addArgument!(info, restrictions)(groups[$-1]);
        }
    }

    void addArgument(ArgumentInfo info, RestrictionGroup[] restrictions = [])()
    {
        static if(info.required)
            addArgument!(info, restrictions)(requiredGroup);
        else
            addArgument!(info, restrictions)(optionalGroup);
    }

    private void addArgument(ArgumentInfo info, RestrictionGroup[] argRestrictions = [])( ref Group group)
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
        group.arguments ~= index;

        static if(info.required)
            restrictions ~= Restrictions.RequiredArg!info(index);

        static foreach(restriction; argRestrictions)
            addRestriction!(info, restriction)(index);
    }

    void addRestriction(ArgumentInfo info, RestrictionGroup restriction)(size_t argIndex)
    {
        auto groupIndex = (restriction.location in groupsByName);
        auto index = groupIndex !is null
        ? *groupIndex
        : {
            auto index = groupsByName[restriction.location] = restrictionGroups.length;
            restrictionGroups ~= restriction;

            static if(restriction.required)
                restrictions ~= (a,b,c) => Restrictions.RequiredAnyOf(a, b, c, restrictionGroups[index].arguments);

            enum checkFunc =
            {
                final switch(restriction.type)
                {
                    case RestrictionGroup.Type.together:  return &Restrictions.RequiredTogether;
                    case RestrictionGroup.Type.exclusive: return &Restrictions.MutuallyExclusive;
                }
            }();

            restrictions ~= (a,b,c) => checkFunc(a, b, c, restrictionGroups[index].arguments);

            return index;
        }();

        restrictionGroups[index].arguments ~= argIndex;
    }


    Result checkRestrictions(in bool[size_t] cliArgs, Config* config) const
    {
        foreach(restriction; restrictions)
        {
            auto res = restriction(config, cliArgs, arguments);
            if(!res)
                return res;
        }

        return Result.Success;
    }


    auto findArgumentImpl(const size_t* pIndex) const
    {
        struct Result
        {
            size_t index = size_t.max;
            const(ArgumentInfo)* arg;
        }

        return pIndex ? Result(*pIndex, &arguments[*pIndex]) : Result.init;
    }

    auto findPositionalArgument(size_t position) const
    {
        return findArgumentImpl(position < argsPositional.length ? &argsPositional[position] : null);
    }

    auto findNamedArgument(string name) const
    {
        return findArgumentImpl(convertCase(name) in argsNamed);
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private template defaultValuesCount(T)
if(!is(T == void))
{
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


package auto setDefaults(TYPE, alias symbol)(ArgumentInfo info)
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
    auto createInfo(string placeholder = "")()
    {
        ArgumentInfo info;
        info.allowBooleanNegation = true;
        info.position = 0;
        info.placeholder = placeholder;
        return info;
    }
    assert(createInfo().allowBooleanNegation); // make codecov happy

    auto res = createInfo().setDefaults!(int, "default-name");
    assert(!res.allowBooleanNegation);
    assert(res.names == [ "default-name" ]);
    assert(res.minValuesCount == defaultValuesCount!int.min);
    assert(res.maxValuesCount == defaultValuesCount!int.max);
    assert(res.placeholder == "default-name");

    res = createInfo!"myvalue".setDefaults!(int, "default-name");
    assert(res.placeholder == "myvalue");
}

unittest
{
    auto createInfo(string placeholder = "")()
    {
        ArgumentInfo info;
        info.allowBooleanNegation = true;
        info.placeholder = placeholder;
        return info;
    }
    assert(createInfo().allowBooleanNegation); // make codecov happy

    auto res = createInfo().setDefaults!(bool, "default_name");
    assert(res.allowBooleanNegation);
    assert(res.names == ["default_name"]);
    assert(res.minValuesCount == defaultValuesCount!bool.min);
    assert(res.maxValuesCount == defaultValuesCount!bool.max);
    assert(res.placeholder == "DEFAULT_NAME");

    res = createInfo!"myvalue".setDefaults!(bool, "default_name");
    assert(res.placeholder == "myvalue");
}

unittest
{
    enum E { a=1, b=1, c }
    static assert(EnumMembersAsStrings!E == ["a","b","c"]);

    auto createInfo(string placeholder = "")()
    {
        ArgumentInfo info;
        info.placeholder = placeholder;
        return info;
    }
    assert(createInfo().allowBooleanNegation); // make codecov happy

    auto res = createInfo().setDefaults!(E, "default-name");
    assert(res.placeholder == "{a,b,c}");

    res = createInfo!"myvalue".setDefaults!(E, "default-name");
    assert(res.placeholder == "myvalue");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package alias ParseFunction(RECEIVER) = Result delegate(Config* config, string argName, ref RECEIVER receiver, string rawValue, ref string[] rawArgs);
package alias ParseSubCommandFunction(RECEIVER) = Result delegate(Config* config, ref Parser parser, const ref Parser.Argument arg, bool isDefaultCmd, ref RECEIVER receiver);
package alias InitSubCommandFunction(RECEIVER) = Result delegate(ref RECEIVER receiver);

package alias ParsingArgument(alias symbol, alias uda, ArgumentInfo info, RECEIVER, bool completionMode) =
    delegate(Config* config, string argName, ref RECEIVER receiver, string rawValue, ref string[] rawArgs)
    {
        static if(completionMode)
        {
            if(rawValue is null)
                consumeValuesFromCLI(rawArgs, info.minValuesCount.get, info.maxValuesCount.get, config.namedArgChar);

            return Result.Success;
        }
        else
        {
            try
            {
                auto rawValues = rawValue !is null ? [ rawValue ] : consumeValuesFromCLI(rawArgs, info.minValuesCount.get, info.maxValuesCount.get, config.namedArgChar);

                auto res = info.checkValuesCount(argName, rawValues.length);
                if(!res)
                    return res;

                auto param = RawParam(config, argName, rawValues);

                auto target = &__traits(getMember, receiver, symbol);

                static if(is(typeof(target) == function) || is(typeof(target) == delegate))
                    return uda.parsingFunc.parse(target, param) ? Result.Success : Result.Failure;
                else
                    return uda.parsingFunc.parse(*target, param) ? Result.Success : Result.Failure;
            }
            catch(Exception e)
            {
                return Result.Error(argName, ": ", e.msg);
            }
        }
    };

package auto ParsingSubCommandArgument(COMMAND_TYPE, CommandInfo info, RECEIVER, alias symbol, bool completionMode)(const CommandArguments!RECEIVER* parentArguments)
{
    return delegate(Config* config, ref Parser parser, const ref Parser.Argument arg, bool isDefaultCmd, ref RECEIVER receiver)
    {
        auto target = &__traits(getMember, receiver, symbol);

        alias parse = (ref COMMAND_TYPE cmdTarget)
        {
            static if(!is(COMMAND_TYPE == Default!TYPE, TYPE))
                alias TYPE = COMMAND_TYPE;

            auto command = CommandArguments!TYPE(config, info, parentArguments);

            return parser.parse!completionMode(command, isDefaultCmd, cmdTarget, arg);
        };


        static if(typeof(*target).Types.length == 1)
            return (*target).match!parse;
        else
        {
            return (*target).match!(parse,
            (_)
            {
                assert(false, "This should never happen");
                return Result.Failure;
            }
            );
        }
    };
}

package alias ParsingSubCommandInit(COMMAND_TYPE, RECEIVER, alias symbol) =
    delegate(ref RECEIVER receiver)
    {
        auto target = &__traits(getMember, receiver, symbol);

        static if(typeof(*target).Types.length > 1)
            if((*target).match!((COMMAND_TYPE t) => false, _ => true))
                *target = COMMAND_TYPE.init;

        return Result.Success;
    };

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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

package bool checkArgumentNames(T)()
{
    enum names = {
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

private void checkArgumentName(T)(char namedArgChar)
{
    import std.exception: enforce;

    static foreach(sym; getSymbolsByUDA!(T, ArgumentUDA))
        static foreach(name; getUDAs!(__traits(getMember, T, __traits(identifier, sym)), ArgumentUDA)[0].info.names)
            enforce(name[0] != namedArgChar, "Name of argument should not begin with '"~namedArgChar~"': "~name);
}

package bool checkPositionalIndexes(T)()
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

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package struct CommandArguments(RECEIVER)
{
    static assert(getSymbolsByUDA!(RECEIVER, TrailingArguments).length <= 1,
    "Type "~RECEIVER.stringof~" must have at most one 'TrailingArguments' UDA");

    private enum _validate = checkArgumentNames!RECEIVER &&
    checkPositionalIndexes!RECEIVER;

    static assert(getUDAs!(RECEIVER, CommandInfo).length <= 1);

    CommandInfo info;
    const(string)[] parentNames;

    Arguments arguments;

    ParseFunction!RECEIVER[] parseArguments;
    ParseFunction!RECEIVER[] completeArguments;

    uint level; // (sub-)command level, 0 = top level

    // sub commands
    size_t[string] subCommandsByName;
    CommandInfo[] subCommands;
    ParseSubCommandFunction!RECEIVER[] parseSubCommands;
    ParseSubCommandFunction!RECEIVER[] completeSubCommands;
    InitSubCommandFunction !RECEIVER[] initSubCommands;

    // completion
    string[] completeSuggestion;


    mixin ForwardMemberFunction!"arguments.findPositionalArgument";
    mixin ForwardMemberFunction!"arguments.findNamedArgument";
    mixin ForwardMemberFunction!"arguments.checkRestrictions";



    this(Config* config)
    {
        static if(getUDAs!(RECEIVER, CommandInfo).length > 0)
            CommandInfo info = getUDAs!(RECEIVER, CommandInfo)[0];
        else
            CommandInfo info;

        this(config, info);
    }

    this(PARENT = void)(Config* config, CommandInfo info, const PARENT* parentArguments = null)
    {
        this.info = info;

        checkArgumentName!RECEIVER(config.namedArgChar);

        static if(is(PARENT == void))
        {
            level = 0;
            arguments = Arguments(config.caseSensitive);
        }
        else
        {
            parentNames = parentArguments.parentNames ~ parentArguments.info.names[0];
            level = parentArguments.level + 1;
            arguments = Arguments(config.caseSensitive, &parentArguments.arguments);
        }

        fillArguments();

        if(config.addHelp)
        {
            arguments.addArgument!helpArgument;
            parseArguments ~= delegate (Config* config, string argName, ref RECEIVER receiver, string rawValue, ref string[] rawArgs)
            {
                import std.stdio: stdout;

                auto output = stdout.lockingTextWriter();
                printHelp(_ => output.put(_), this, config);

                return Result(0);
            };
            completeArguments ~= delegate (Config* config, string argName, ref RECEIVER receiver, string rawValue, ref string[] rawArgs)
            {
                return Result.Success;
            };
        }


        import std.algorithm: sort, map;
        import std.range: join;
        import std.array: array;

        completeSuggestion = arguments.argsNamed.keys.map!(_ => getArgumentName(_, config)).array;
        completeSuggestion ~= subCommandsByName.keys.array;
        completeSuggestion.sort;
    }

    private void fillArguments()
    {
        enum hasNoUDAs = getSymbolsByUDA!(RECEIVER, ArgumentUDA  ).length == 0 &&
        getSymbolsByUDA!(RECEIVER, NamedArgument).length == 0 &&
        getSymbolsByUDA!(RECEIVER, SubCommands  ).length == 0;

        static foreach(sym; __traits(allMembers, RECEIVER))
        {{
            alias mem = __traits(getMember, RECEIVER, sym);

            static if(!is(mem)) // skip types
            {
                static if(hasUDA!(mem, ArgumentUDA) || hasUDA!(mem, NamedArgument))
                    addArgument!sym;
                else static if(hasUDA!(mem, SubCommands))
                    addSubCommands!sym;
                else static if(hasNoUDAs &&
                    // skip "op*" functions
                    !(is(typeof(mem) == function) && sym.length > 2 && sym[0..2] == "op"))
                    {
                        import std.sumtype: isSumType;

                        static if(isSumType!(typeof(mem)))
                            addSubCommands!sym;
                        else
                            addArgument!sym;
                    }
            }
        }}
    }

    private void addArgument(alias symbol)()
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
            arguments.addArgument!(info, restrictions, getUDAs!(member, Group)[0]);
        else
        arguments.addArgument!(info, restrictions);

        parseArguments    ~= ParsingArgument!(symbol, uda, info, RECEIVER, false);
        completeArguments ~= ParsingArgument!(symbol, uda, info, RECEIVER, true);
    }

    private void addSubCommands(alias symbol)()
    {
        import std.sumtype: isSumType;

        alias member = __traits(getMember, RECEIVER, symbol);

        static assert(isSumType!(typeof(member)), RECEIVER.stringof~"."~symbol~" must have 'SumType' type");

        static assert(getUDAs!(member, SubCommands).length <= 1,
        "Member "~RECEIVER.stringof~"."~symbol~" has multiple 'SubCommands' UDAs");

        static foreach(TYPE; typeof(member).Types)
        {{
            enum defaultCommand = is(TYPE == Default!COMMAND_TYPE, COMMAND_TYPE);
            static if(!defaultCommand)
                alias COMMAND_TYPE = TYPE;

            static assert(getUDAs!(COMMAND_TYPE, CommandInfo).length <= 1);

            //static assert(getUDAs!(member, Group).length <= 1,
            //    "Member "~RECEIVER.stringof~"."~symbol~" has multiple 'Group' UDAs");

            static if(getUDAs!(COMMAND_TYPE, CommandInfo).length > 0)
                enum info = getUDAs!(COMMAND_TYPE, CommandInfo)[0];
            else
                enum info = CommandInfo([COMMAND_TYPE.stringof]);

            static assert(info.names.length > 0 && info.names[0].length > 0);

            //static if(getUDAs!(member, Group).length > 0)
            //    args.addArgument!(info, restrictions, getUDAs!(member, Group)[0])(ParsingArgument!(symbol, uda, info, RECEIVER));
            //else
            //arguments.addSubCommand!(info);

            immutable index = subCommands.length;

            static foreach(name; info.names)
            {
                assert(!(name in subCommandsByName), "Duplicated name of subcommand: "~name);
                subCommandsByName[arguments.convertCase(name)] = index;
            }

            static if(defaultCommand)
            {
                assert(!(DEFAULT_COMMAND in subCommandsByName), "Multiple default subcommands: "~RECEIVER.stringof~"."~symbol);
                subCommandsByName[DEFAULT_COMMAND] = index;
            }

            subCommands ~= info;
            //group.arguments ~= index;
            parseSubCommands    ~= ParsingSubCommandArgument!(TYPE, info, RECEIVER, symbol, false)(&this);
            completeSubCommands ~= ParsingSubCommandArgument!(TYPE, info, RECEIVER, symbol, true)(&this);
            initSubCommands     ~= ParsingSubCommandInit!(TYPE, RECEIVER, symbol);
        }}
    }

    auto getParseFunction(bool completionMode)(size_t index) const
    {
        static if(completionMode)
            return completeArguments[index];
        else
            return parseArguments[index];
    }

    auto findSubCommand(string name) const
    {
        struct Result
        {
            uint level = uint.max;
            ParseSubCommandFunction!RECEIVER parse;
            ParseSubCommandFunction!RECEIVER complete;
            InitSubCommandFunction !RECEIVER initialize;
        }

        auto p = arguments.convertCase(name) in subCommandsByName;
        return !p ? Result.init : Result(level+1, parseSubCommands[*p], completeSubCommands[*p], initSubCommands[*p]);
    }

    package void setTrailingArgs(ref RECEIVER receiver, ref string[] rawArgs) const
    {
        static if(getSymbolsByUDA!(RECEIVER, TrailingArguments).length == 1)
        {
            enum symbol = __traits(identifier, getSymbolsByUDA!(RECEIVER, TrailingArguments)[0]);
            auto target = &__traits(getMember, receiver, symbol);

            static if(__traits(compiles, { *target = rawArgs; }))
                *target = rawArgs;
            else
                static assert(false, "Type '"~typeof(*target).stringof~"' of `"~
                                     RECEIVER.stringof~"."~symbol~"` is not supported for 'TrailingArguments' UDA");

            rawArgs = [];
        }
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private template DefaultValueParseFunctions(T)
if(!is(T == void))
{
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
            Config config;
            DefaultValueParseFunctions!R.parse(receiver, RawParam(&config, "", [""]));
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
            assert(DefaultValueParseFunctions!R.parse(receiver, RawParam(&config, "", value)));
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
        Config config;
        assert(DefaultValueParseFunctions!T.parse(receiver, RawParam(&config, "", values)));
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

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package struct ValueParseFunctions(alias PreProcess,
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

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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
    auto test(alias F, T)()
    {
        Config config;
        return ValidateFunc!(F, T)(RawParam(&config, "", ["1","2","3"]));
    }
    static assert(test!(void, string[]));

    static assert(!__traits(compiles, { test!(() {}, string[]); }));
    static assert(!__traits(compiles, { test!((int,int) {}, string[]); }));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package struct Validators
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

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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

        auto param = RawParam(&config, "", values);

        splitValues(param);

        return param.value;
    };

    static assert(test(',', []) == []);
    static assert(test(',', ["a","b","c"]) == ["a","b","c"]);
    static assert(test(',', ["a,b","c","d,e,f"]) == ["a","b","c","d","e","f"]);
    static assert(test(' ', ["a,b","c","d,e,f"]) == ["a,b","c","d,e,f"]);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
