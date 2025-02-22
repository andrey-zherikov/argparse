module argparse.internal.command;

import argparse.config;
import argparse.param;
import argparse.result;
import argparse.api.argument: NamedArgument, NumberOfValues;
import argparse.api.subcommand: match, isSubCommand;
import argparse.internal.arguments: Arguments, ArgumentInfo, finalize;
import argparse.internal.argumentuda: ArgumentUDA;
import argparse.internal.argumentudahelpers: getMemberArgumentUDA, isArgumentUDA;
import argparse.internal.commandinfo;
import argparse.internal.help: HelpArgumentUDA;
import argparse.internal.restriction;

import std.typecons: Nullable, nullable;
import std.traits: getSymbolsByUDA, hasUDA, getUDAs;


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package struct SubCommands
{
    size_t[string] byName;

    CommandInfo[] info;


    void add(CommandInfo[] cmdInfo)
    {
        info = cmdInfo;

        foreach(index, info; cmdInfo)
            foreach(name; info.names)
            {
                assert(!(name in byName), "Duplicated name of subcommand: "~name);
                byName[name] = index;
            }
    }
}


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private Result ArgumentParsingFunction(alias uda, RECEIVER)(const Command[] cmdStack,
                                                            ref RECEIVER receiver,
                                                            ref RawParam param)
{
    static if(uda.info.memberSymbol)
        auto target = &__traits(getMember, receiver, uda.info.memberSymbol);
    else
        auto target = null;

    static if(is(typeof(target) == typeof(null)) || is(typeof(target) == function) || is(typeof(target) == delegate))
        return uda.parse(cmdStack, target, param);
    else
        return uda.parse(cmdStack, *target, param);
}

private Result ArgumentCompleteFunction(alias uda, RECEIVER)(const Command[] cmdStack,
                                                             ref RECEIVER receiver,
                                                             ref RawParam param)
{
    return Result.Success;
}


unittest
{
    struct T { string a; }

    auto test(string[] values)
    {
        T t;
        Config cfg;
        auto param = RawParam(&cfg, "a", values);

        enum uda = getMemberArgumentUDA!(T, "a")(Config.init);

        return ArgumentParsingFunction!uda([], t, param);
    }

    assert(test(["raw-value"]));
    assert(!test(["value1","value2"]));
}

unittest
{
    struct T
    {
        void func() { throw new Exception("My Message."); }
    }

    T t;
    Config cfg;
    auto param = RawParam(&cfg, "func", []);

    enum uda = getMemberArgumentUDA!(T, "func")(Config.init);

    auto res = ArgumentParsingFunction!uda([], t, param);

    assert(res.isError("func",": My Message."));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package struct Command
{
    alias Parse = Result delegate(const Command[] cmdStack,ref RawParam param);

    struct Argument
    {
        const(ArgumentInfo)* info;

        Parse parse;
        Parse complete;

        bool opCast(T : bool)() const
        {
            return info !is null;
        }
    }

    private Parse[] parseFuncs;
    private Parse[] completeFuncs;

    private Parse getParseFunc(Parse[] funcs, size_t index)
    {
        return (stack, ref param)
        {
            idxParsedArgs[index] = true;
            return funcs[index](stack, param);
        };
    }


    auto findNamedArgument(string name)
    {
        auto res = arguments.findNamedArgument(name);
        if(!res.arg)
            return Argument.init;

        return Argument(res.arg, getParseFunc(parseFuncs, res.index), getParseFunc(completeFuncs, res.index));
    }

    auto findPositionalArgument(size_t position)
    {
        auto res = arguments.findPositionalArgument(position);
        if(!res.arg)
            return Argument.init;

        return Argument(res.arg, getParseFunc(parseFuncs, res.index), getParseFunc(completeFuncs, res.index));
    }



    const(string)[] suggestions(string prefix) const
    {
        import std.range: chain;
        import std.algorithm: filter, map;
        import std.string: startsWith;
        import std.array: array, join;

        // suggestions are names of all arguments and subcommands
        auto suggestions_ = chain(arguments.namedArguments.filter!((ref _) => !_.hidden).map!((ref _) => _.displayNames).join, subCommands.byName.keys);

        // empty prefix means that we need to provide all suggestions, otherwise they are filtered
        return prefix == "" ? suggestions_.array : suggestions_.filter!(_ => _.startsWith(prefix)).array;
    }


    Arguments arguments;

    bool[size_t] idxParsedArgs;

    Restrictions restrictions;

    CommandInfo info;

    string displayName() const { return info.displayNames.length > 0 ? info.displayNames[0] : ""; }

    SubCommands subCommands;
    Command delegate() [] subCommandCreate;
    Command delegate() defaultSubCommand;

    auto getSubCommand(string name) const
    {
        auto pIndex = name in subCommands.byName;
        if(pIndex is null)
            return null;

        return subCommandCreate[*pIndex];
    }

    Result checkRestrictions() const
    {
        return restrictions.check(idxParsedArgs);
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private enum hasNoMembersWithUDA(COMMAND) = getSymbolsByUDA!(COMMAND, ArgumentUDA   ).length == 0 &&
                                            getSymbolsByUDA!(COMMAND, NamedArgument ).length == 0;

private enum isOpFunction(alias mem) = is(typeof(mem) == function) && __traits(identifier, mem).length > 2 && __traits(identifier, mem)[0..2] == "op";
private enum isConstructor(alias mem) = is(typeof(mem) == function) && __traits(identifier, mem) == "__ctor";

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private template iterateArguments(TYPE)
{
    import std.meta: Filter, anySatisfy;

    // In case if TYPE is no members with ArgumentUDA, we filter out "op..." functions and ctors
    // Otherwise, we pick members with ArgumentUDA
    static if(hasNoMembersWithUDA!TYPE)
        enum isValidArgumentMember(alias mem) = !isOpFunction!mem && !isConstructor!mem;
    else
        enum isValidArgumentMember(alias mem) = anySatisfy!(isArgumentUDA, __traits(getAttributes, mem));

    template filter(string sym)
    {
        alias mem = __traits(getMember, TYPE, sym);

        enum filter =
            !is(mem) &&                     // not a type       -- and --
            !isSubCommand!(typeof(mem)) &&  // not subcommand   -- and --
            isValidArgumentMember!mem;      // is valid argument member
    }

    alias iterateArguments = Filter!(filter, __traits(allMembers, TYPE));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private template subCommandSymbol(TYPE)
{
    import std.meta: Filter, AliasSeq;

    template filter(string sym)
    {
        alias mem = __traits(getMember, TYPE, sym);

        enum filter = !is(mem) && isSubCommand!(typeof(mem));
    }

    alias symbols = Filter!(filter, __traits(allMembers, TYPE));

    static if(symbols.length == 0)
        enum subCommandSymbol = "";
    else static if(symbols.length == 1)
        enum subCommandSymbol = symbols[0];
    else
        static assert(false, "Multiple subcommand members are in "~TYPE.stringof~": "~symbols.stringof);

}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private struct SubCommand(TYPE)
{
    alias Type = TYPE;

    CommandInfo info;
}

private template TypeTraits(Config config, TYPE)
{
    import std.meta: AliasSeq, Filter, staticMap, staticSort;
    import std.range: chain;

    /////////////////////////////////////////////////////////////////////
    /// Arguments

    private enum getArgumentUDA(string sym) = getMemberArgumentUDA!(TYPE, sym)(config);
    private enum getArgumentInfo(alias uda) = uda.info;
    private enum positional(ArgumentInfo info) = info.positional;
    private enum comparePosition(ArgumentInfo info1, ArgumentInfo info2) = info1.position.get - info2.position.get;

    static if(config.addHelpArgument)
    {
        private enum helpUDA = HelpArgumentUDA(HelpArgumentUDA.init.info.finalize!bool(config, null));
        enum argumentUDAs = AliasSeq!(staticMap!(getArgumentUDA, iterateArguments!TYPE), helpUDA);
    }
    else
        enum argumentUDAs = staticMap!(getArgumentUDA, iterateArguments!TYPE);

    enum argumentInfos = staticMap!(getArgumentInfo, argumentUDAs);


    /////////////////////////////////////////////////////////////////////
    /// Subcommands

    private enum getCommandInfo(CMD) = .getSubCommandInfo!CMD(config);
    private enum getSubcommand(CMD) = SubCommand!CMD(getCommandInfo!CMD);

    static if(.subCommandSymbol!TYPE.length == 0)
        private alias subCommandTypes = AliasSeq!();
    else
    {
        enum subCommandSymbol = .subCommandSymbol!TYPE;
        private alias subCommandMemberType = typeof(__traits(getMember, TYPE, subCommandSymbol));
        private alias subCommandTypes = subCommandMemberType.Types;

        enum isDefaultSubCommand(T) = is(subCommandMemberType.DefaultCommand == T);
    }

    enum subCommands = staticMap!(getSubcommand, subCommandTypes);
    enum subCommandInfos = staticMap!(getCommandInfo, subCommandTypes);


    /////////////////////////////////////////////////////////////////////
    /// Static checks whether TYPE does not violate argparse requirements

    private enum positionalArgInfos = staticSort!(comparePosition, Filter!(positional, argumentInfos));

    static foreach(info; argumentInfos)
        static foreach (name; chain(info.shortNames, info.longNames))
            static assert(name[0] != config.namedArgPrefix, TYPE.stringof~": Argument name should not begin with '"~config.namedArgPrefix~"': "~name);

    static foreach(int i, info; positionalArgInfos)
        static assert({
            enum int pos = info.position.get;

            static if(i < pos)
                static assert(false, TYPE.stringof~": Positional argument with index "~i.stringof~" is missed");
            else static if(i > pos)
                static assert(false, TYPE.stringof~": Positional argument with index "~pos.stringof~" is duplicated");

            static if(pos < positionalArgInfos.length - 1)
                static assert(info.minValuesCount.get == info.maxValuesCount.get,
                    TYPE.stringof~": Positional argument with index "~pos.stringof~" has variable number of values.");

            static if(i > 0 && info.required)
                static assert(positionalArgInfos[i-1].required, TYPE.stringof~": Required positional argument with index "~pos.stringof~" comes after optional positional argument");

            return true;
        }());

    static if(is(subCommandMemberType))
    {
        static if(positionalArgInfos.length > 0 && is(subCommandMemberType.DefaultCommand))
            static assert(positionalArgInfos[$-1].required, TYPE.stringof~": Optional positional arguments and default subcommand are used together in one command");
    }

    static foreach(info; subCommandInfos)
        static foreach(name; info.names)
            static assert(name[0] != config.namedArgPrefix, TYPE.stringof~": Subcommand name should not begin with '"~config.namedArgPrefix~"': "~name);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) Command createCommand(Config config, COMMAND_TYPE)(ref COMMAND_TYPE receiver, CommandInfo info)
{
    import std.meta: staticMap;
    import std.algorithm: map;
    import std.array: array;

    alias typeTraits = TypeTraits!(config, COMMAND_TYPE);

    Command res;

    res.info = info;
    res.arguments.add!(COMMAND_TYPE, [typeTraits.argumentInfos]);
    res.restrictions.add!(COMMAND_TYPE, [typeTraits.argumentInfos])(config);

    enum getArgumentParsingFunction(alias uda) =
         (const Command[] cmdStack, ref RawParam param) => ArgumentParsingFunction!uda(cmdStack, receiver, param);

    res.parseFuncs = [staticMap!(getArgumentParsingFunction, typeTraits.argumentUDAs)];

    enum getArgumentCompleteFunction(alias uda) =
        (const Command[] cmdStack, ref RawParam param) => ArgumentCompleteFunction!uda(cmdStack, receiver, param);

    res.completeFuncs = [staticMap!(getArgumentCompleteFunction, typeTraits.argumentUDAs)];

    res.subCommands.add([typeTraits.subCommandInfos]);

    static foreach(subcmd; typeTraits.subCommands)
    {{
        auto createFunc = () => ParsingSubCommandCreate!(config, subcmd.Type)(
            __traits(getMember, receiver, typeTraits.subCommandSymbol),
            subcmd.info,
        );

        static if(typeTraits.isDefaultSubCommand!(subcmd.Type))
            res.defaultSubCommand = createFunc;

        res.subCommandCreate ~= createFunc;
    }}

    return res;
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private auto ParsingSubCommandCreate(Config config, COMMAND_TYPE, TARGET)(ref TARGET target, CommandInfo info)
{
    alias create = (ref COMMAND_TYPE actualTarget) =>
        createCommand!(config, COMMAND_TYPE)(actualTarget, info);

    // Initialize if needed
    if(!target.isSetTo!COMMAND_TYPE)
        target = COMMAND_TYPE.init;

    static if(TARGET.Types.length == 1)
        return target.match!create;
    else
    {
        return target.match!(create,
            function Command(_)
            {
                assert(false, "This should never happen");
            }
        );
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
