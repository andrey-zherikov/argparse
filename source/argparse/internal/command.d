module argparse.internal.command;

import argparse.config;
import argparse.param;
import argparse.result;
import argparse.api.argument: TrailingArguments, NamedArgument, NumberOfValues;
import argparse.api.command: isDefaultCommand, RemoveDefaultAttribute, SubCommandsUDA = SubCommands;
import argparse.internal.arguments: Arguments, ArgumentInfo;
import argparse.internal.argumentuda: ArgumentUDA, getMemberArgumentUDA;
import argparse.internal.commandinfo;
import argparse.internal.help: HelpArgumentUDA;
import argparse.internal.restriction;

import std.typecons: Nullable, nullable;
import std.traits: getSymbolsByUDA, hasUDA, getUDAs;
import std.sumtype: match, isSumType;


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

private Result ArgumentParsingFunction(Config config, alias uda, RECEIVER)(const Command[] cmdStack,
                                                                           ref RECEIVER receiver,
                                                                           string argName,
                                                                           string[] rawValues)
{
    static if(is(typeof(uda.parse)))
        return uda.parse!config(cmdStack, receiver, argName, rawValues);
    else
        try
        {
            auto res = uda.info.checkValuesCount(config, argName, rawValues.length);
            if(!res)
                return res;

            const cfg = config;
            auto param = RawParam(&cfg, argName, rawValues);

            auto target = &__traits(getMember, receiver, uda.info.memberSymbol);

            static if(is(typeof(target) == function) || is(typeof(target) == delegate))
                return uda.parsingFunc.parse(target, param);
            else
                return uda.parsingFunc.parse(*target, param);
        }
        catch(Exception e)
        {
            return Result.Error("Argument '", config.styling.argumentName(argName), ": ", e.msg);
        }
}

private Result ArgumentCompleteFunction(Config config, alias uda, RECEIVER)(const Command[] cmdStack,
                                                                              ref RECEIVER receiver,
                                                                              string argName,
                                                                              string[] rawValues)
{
    return Result.Success;
}


unittest
{
    struct T { string a; }

    auto test(string[] values)
    {
        T t;

        enum uda = getMemberArgumentUDA!(T, "a")(Config.init, NamedArgument("arg-name").NumberOfValues(1));

        return ArgumentParsingFunction!(Config.init, uda)([], t, "arg-name", values);
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

    enum uda = getMemberArgumentUDA!(T, "func")(Config.init, NamedArgument("arg-name").NumberOfValues(0));

    auto res = ArgumentParsingFunction!(Config.init, uda)([], t, "arg-name", []);

    assert(res.isError(Config.init.styling.argumentName("arg-name")~": My Message."));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package struct Command
{
    alias Parse = Result delegate(const Command[] cmdStack, string argName, string[] argValue);

    struct Argument
    {
        size_t index = size_t.max;

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

    auto findNamedArgument(string name) const
    {
        auto res = arguments.findNamedArgument(name);
        if(!res.arg)
            return Argument.init;

        return Argument(res.index, res.arg, parseFuncs[res.index], completeFuncs[res.index]);
    }

    auto findPositionalArgument(size_t position) const
    {
        auto res = arguments.findPositionalArgument(position);
        if(!res.arg)
            return Argument.init;

        return Argument(res.index, res.arg, parseFuncs[res.index], completeFuncs[res.index]);
    }


    void delegate(ref string[] args) setTrailingArgs;



    const(string)[] suggestions(string prefix) const
    {
        import std.range: chain;
        import std.algorithm: filter, map;
        import std.string: startsWith;
        import std.array: array, join;

        // suggestions are names of all arguments and subcommands
        auto suggestions_ = chain(arguments.namedArguments.map!(_ => _.displayNames).join, subCommands.byName.keys);

        // empty prefix means that we need to provide all suggestions, otherwise they are filtered
        return prefix == "" ? suggestions_.array : suggestions_.filter!(_ => _.startsWith(prefix)).array;
    }


    Arguments arguments;

    Restrictions restrictions;

    CommandInfo info;

    string displayName() const { return info.displayNames[0]; }

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

    Result checkRestrictions(in bool[size_t] cliArgs) const
    {
        return restrictions.check(cliArgs);
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private enum hasNoMembersWithUDA(COMMAND) = getSymbolsByUDA!(COMMAND, ArgumentUDA   ).length == 0 &&
                                            getSymbolsByUDA!(COMMAND, NamedArgument ).length == 0 &&
                                            getSymbolsByUDA!(COMMAND, SubCommands).length == 0;

private enum isOpFunction(alias mem) = is(typeof(mem) == function) && __traits(identifier, mem).length > 2 && __traits(identifier, mem)[0..2] == "op";

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private template iterateArguments(TYPE)
{
    import std.meta: Filter;
    import std.sumtype: isSumType;

    template filter(string sym)
    {
        alias mem = __traits(getMember, TYPE, sym);

        enum filter = !is(mem) && (
            hasUDA!(mem, ArgumentUDA) ||
            hasUDA!(mem, NamedArgument) ||
            hasNoMembersWithUDA!TYPE && !isOpFunction!mem && !isSumType!(typeof(mem)));
    }

    alias iterateArguments = Filter!(filter, __traits(allMembers, TYPE));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private template subCommandSymbol(TYPE)
{
    import std.meta: Filter, AliasSeq;
    import std.sumtype: isSumType;

    template filter(string sym)
    {
        alias mem = __traits(getMember, TYPE, sym);

        enum filter = !is(mem) && (
            hasUDA!(mem, SubCommandsUDA) ||
            hasNoMembersWithUDA!TYPE && !isOpFunction!mem && isSumType!(typeof(mem)));
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
    import argparse.internal.arguments: finalize;
    import std.meta: AliasSeq, Filter, staticMap, staticSort;
    import std.range: chain;

    /////////////////////////////////////////////////////////////////////
    /// Arguments

    private enum getArgumentUDA(string sym) = getMemberArgumentUDA!(TYPE, sym)(config, NamedArgument);
    private enum getArgumentInfo(alias uda) = uda.info;
    private enum positional(ArgumentInfo info) = info.positional;
    private enum comparePosition(ArgumentInfo info1, ArgumentInfo info2) = info1.position.get - info2.position.get;

    static if(config.addHelp)
    {
        private enum helpUDA = HelpArgumentUDA(HelpArgumentUDA.init.info.finalize!bool(config, null));
        enum argumentUDAs = AliasSeq!(staticMap!(getArgumentUDA, iterateArguments!TYPE), helpUDA);
    }
    else
        enum argumentUDAs = staticMap!(getArgumentUDA, iterateArguments!TYPE);

    enum argumentInfos = staticMap!(getArgumentInfo, argumentUDAs);


    /////////////////////////////////////////////////////////////////////
    /// Subcommands

    private enum getCommandInfo(CMD) = .getCommandInfo!(RemoveDefaultAttribute!CMD)(config, RemoveDefaultAttribute!CMD.stringof);
    private enum getSubcommand(CMD) = SubCommand!CMD(getCommandInfo!CMD);

    static if(.subCommandSymbol!TYPE.length == 0)
        private alias subCommandTypes = AliasSeq!();
    else
    {
        enum subCommandSymbol = .subCommandSymbol!TYPE;
        private alias subCommandTypes = AliasSeq!(typeof(__traits(getMember, TYPE, subCommandSymbol)).Types);
    }

    enum subCommands = staticMap!(getSubcommand, subCommandTypes);
    enum subCommandInfos = staticMap!(getCommandInfo, subCommandTypes);

    private alias defaultSubCommands = Filter!(isDefaultCommand, subCommandTypes);

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

    static if(is(subCommandSymbol))
    {
        static assert(defaultSubCommands.length <= 1, TYPE.stringof~": Multiple default subcommands in "~TYPE.stringof~"."~subCommandSymbol);

        static if(positionalArgInfos.length > 0 && defaultSubCommands.length > 0)
            static assert(positionalArgInfos[$-1].required, TYPE.stringof~": Optional positional arguments and default subcommand are used together in one command");
    }
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
         (const Command[] cmdStack, string argName, string[] argValue)
         => ArgumentParsingFunction!(config, uda)(cmdStack, receiver, argName, argValue);

    res.parseFuncs = [staticMap!(getArgumentParsingFunction, typeTraits.argumentUDAs)];

    enum getArgumentCompleteFunction(alias uda) =
        (const Command[] cmdStack, string argName, string[] argValue)
        => ArgumentCompleteFunction!(config, uda)(cmdStack, receiver, argName, argValue);

    res.completeFuncs = [staticMap!(getArgumentCompleteFunction, typeTraits.argumentUDAs)];

    res.setTrailingArgs = (ref string[] args)
    {
        .setTrailingArgs(receiver, args);
    };

    res.subCommands.add([typeTraits.subCommandInfos]);

    static foreach(subcmd; typeTraits.subCommands)
    {{
        auto createFunc = () => ParsingSubCommandCreate!(config, subcmd.Type)(
            __traits(getMember, receiver, typeTraits.subCommandSymbol),
            subcmd.info,
        );

        static if(isDefaultCommand!(subcmd.Type))
            res.defaultSubCommand = createFunc;

        res.subCommandCreate ~= createFunc;
    }}

    return res;
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private auto ParsingSubCommandCreate(Config config, COMMAND_TYPE, TARGET)(ref TARGET target, CommandInfo info)
{
    alias create = (ref COMMAND_TYPE actualTarget) =>
        createCommand!(config, RemoveDefaultAttribute!COMMAND_TYPE)(actualTarget, info);

    static if(TARGET.Types.length == 1)
        return target.match!create;
    else
    {
        // Initialize if needed
        if(target.match!((ref COMMAND_TYPE t) => false, _ => true))
            target = COMMAND_TYPE.init;

        return target.match!(create,
            function Command(_)
            {
                assert(false, "This should never happen");
            }
        );
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private void setTrailingArgs(RECEIVER)(ref RECEIVER receiver, ref string[] rawArgs)
{
    alias ORIG_TYPE = RemoveDefaultAttribute!RECEIVER;

    alias symbols = getSymbolsByUDA!(ORIG_TYPE, TrailingArguments);

    static assert(symbols.length <= 1, "Type "~ORIG_TYPE.stringof~" must have at most one 'TrailingArguments' UDA");
    static if(symbols.length == 1)
    {
        enum symbol = __traits(identifier, symbols[0]);
        auto target = &__traits(getMember, receiver, symbol);

        static if(__traits(compiles, { *target = rawArgs; }))
            *target = rawArgs;
        else
            static assert(false, "Type '"~typeof(*target).stringof~"' of `"~ORIG_TYPE.stringof~"."~symbol~"` is not supported for 'TrailingArguments' UDA");

        rawArgs = [];
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
