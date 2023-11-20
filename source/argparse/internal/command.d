module argparse.internal.command;

import argparse.config;
import argparse.param;
import argparse.result;
import argparse.api.argument: TrailingArguments, NamedArgument, NumberOfValues;
import argparse.api.command: isDefaultCommand, RemoveDefaultAttribute, SubCommandsUDA = SubCommands;
import argparse.internal.arguments: Arguments, ArgumentInfo;
import argparse.internal.argumentuda: ArgumentUDA, getArgumentUDA, getMemberArgumentUDA;
import argparse.internal.commandinfo;
import argparse.internal.hooks: HookHandlers;
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

private alias ParseFunction(COMMAND_STACK, RECEIVER) = Result delegate(const COMMAND_STACK cmdStack, Config* config, ref RECEIVER receiver, string argName, string[] rawValues);

private alias ParsingArgumentFunction(COMMAND_STACK, RECEIVER, alias symbol, alias uda) =
    delegate(const COMMAND_STACK cmdStack, Config* config, ref RECEIVER receiver, string argName, string[] rawValues)
    {
        try
        {
            auto res = uda.info.checkValuesCount(argName, rawValues.length);
            if(!res)
                return res;

                auto param = RawParam(config, argName, rawValues);

            auto target = &__traits(getMember, receiver, uda.info.memberSymbol);

            static if(is(typeof(target) == function) || is(typeof(target) == delegate))
                return uda.parsingFunc.parse(target, param);
            else
                return uda.parsingFunc.parse(*target, param);
        }
        catch(Exception e)
        {
            return Result.Error(argName, ": ", e.msg);
        }
    };

private alias CompletingArgumentFunction(Config config, COMMAND_STACK, RECEIVER, alias symbol, alias uda) =
    delegate(const COMMAND_STACK cmdStack, Config* config, ref RECEIVER receiver, string argName, string[] rawValues)
        => Result.Success;


unittest
{
    struct T { string a; }

    auto test(TYPE)(string[] values)
    {
        Config config;
        TYPE t;

        enum uda = getMemberArgumentUDA!(Config.init, TYPE, "a", NamedArgument("arg-name").NumberOfValues(1));

        return ParsingArgumentFunction!(string[], TYPE, "a", uda)([], &config, t, "arg-name", values);
    }

    assert(test!T(["raw-value"]));
    assert(!test!T(["value1","value2"]));
}

unittest
{
    struct T
    {
        void func() { throw new Exception("My Message."); }
    }

    Config config;
    T t;

    enum uda = getMemberArgumentUDA!(Config.init, T, "func", NamedArgument("arg-name").NumberOfValues(0));

    auto res = ParsingArgumentFunction!(string[], T, "func", uda)([], &config, t, "arg-name", []);

    assert(res.isError("arg-name: My Message."));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private auto getArgumentParsingFunctions(Config config, COMMAND_STACK, TYPE, udas...)()
{
    ParseFunction!(COMMAND_STACK, TYPE)[] res;

    static foreach(uda; udas)
    {
        static if(is(typeof(uda.parse)))
            res ~= (const COMMAND_STACK cmdStack, Config* config, ref TYPE receiver, string argName, string[] rawValues)
                    => uda.parse(cmdStack, config, receiver, argName, rawValues);
        else
            res ~= ParsingArgumentFunction!(COMMAND_STACK, TYPE, uda.info.memberSymbol, uda);
    }

    return res;
}

private auto getArgumentCompletionFunctions(Config config, COMMAND_STACK, TYPE, udas...)()
{
    ParseFunction!(COMMAND_STACK, TYPE)[] res;

    static foreach(uda; udas)
        res ~= CompletingArgumentFunction!(config, COMMAND_STACK, TYPE, uda.info.memberSymbol, uda);

    return res;
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package struct Command
{
    bool isDefault;

    Arguments.FindResult findNamedArgument(string name) const
    {
        return arguments.findNamedArgument(name);
    }
    Arguments.FindResult findPositionalArgument(size_t position) const
    {
        return arguments.findPositionalArgument(position);
    }

    alias ParseFunction = Result delegate(const Command[] cmdStack, Config* config, string argName, string[] argValue);
    ParseFunction[] parseFunctions;
    ParseFunction[] completeFunctions;

    Result parseArgument(const Command[] cmdStack, Config* config, size_t argIndex, string argName, string[] argValue) const
    {
        return parseFunctions[argIndex](cmdStack, config, argName, argValue);
    }
    Result completeArgument(const Command[] cmdStack, Config* config, size_t argIndex, string argName, string[] argValue) const
    {
        return completeFunctions[argIndex](cmdStack, config, argName, argValue);
    }

    void delegate(ref string[] args) setTrailingArgs;



    const(string)[] suggestions(string prefix) const
    {
        import std.range: chain;
        import std.algorithm: filter, map;
        import std.string: startsWith;
        import std.array: array, join;

        // suggestions are names of all arguments and subcommands
        auto suggestions_ = chain(arguments.arguments.map!(_ => _.displayNames).join, subCommands.byName.keys);

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

    auto getDefaultSubCommand(const Command[] cmdStack) const
    {
        return defaultSubCommand is null ? Nullable!Command.init : nullable(defaultSubCommand());
    }

    auto getSubCommand(const Command[] cmdStack, string name) const
    {
        auto pIndex = name in subCommands.byName;
        if(pIndex is null)
            return Nullable!Command.init;

        return nullable(subCommandCreate[*pIndex]());
    }

    HookHandlers hooks;

    void onParsingDone(const Config* config) const
    {
        hooks.onParsingDone(config);
    }

    Result checkRestrictions(in bool[size_t] cliArgs, Config* config) const
    {
        return restrictions.check(cliArgs);
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private enum hasNoMembersWithUDA(COMMAND) = getSymbolsByUDA!(COMMAND, ArgumentUDA  ).length == 0 &&
                                            getSymbolsByUDA!(COMMAND, NamedArgument).length == 0 &&
                                            getSymbolsByUDA!(COMMAND, SubCommands  ).length == 0;

private enum isOpFunction(alias mem) = is(typeof(mem) == function) && __traits(identifier, mem).length > 2 && __traits(identifier, mem)[0..2] == "op";
private enum isConstructor(alias mem) = is(typeof(mem) == function) && __traits(identifier, mem) == "__ctor";

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private template iterateArguments(TYPE)
{
    import std.meta: Filter;
    import std.sumtype: isSumType;

    template filter(alias sym)
    {
        alias mem = __traits(getMember, TYPE, sym);

        enum filter = !is(mem) && (
            hasUDA!(mem, ArgumentUDA) ||
            hasUDA!(mem, NamedArgument) ||
            hasNoMembersWithUDA!TYPE && !isOpFunction!mem && !isConstructor!mem && !isSumType!(typeof(mem)));
    }

    alias iterateArguments = Filter!(filter, __traits(allMembers, TYPE));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private template subCommandSymbol(TYPE)
{
    import std.meta: Filter, AliasSeq;
    import std.sumtype: isSumType;

    template filter(alias sym)
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
    import std.meta: AliasSeq, Filter, staticMap, staticSort;

    /////////////////////////////////////////////////////////////////////
    /// Arguments

    private enum getArgumentUDA(alias sym) = getMemberArgumentUDA!(config, TYPE, sym, NamedArgument);
    private enum getArgumentInfo(alias uda) = uda.info;
    private enum positional(ArgumentInfo info) = info.positional;
    private enum comparePosition(ArgumentInfo info1, ArgumentInfo info2) = info1.position.get - info2.position.get;

    static if(config.addHelp)
    {
        private enum helpUDA = .getArgumentUDA!(config, bool, null, HelpArgumentUDA.init);
        enum argumentUDAs = AliasSeq!(staticMap!(getArgumentUDA, iterateArguments!TYPE), helpUDA);
    }
    else
        enum argumentUDAs = staticMap!(getArgumentUDA, iterateArguments!TYPE);

    enum argumentInfos = staticMap!(getArgumentInfo, argumentUDAs);


    /////////////////////////////////////////////////////////////////////
    /// Subcommands

    private enum getCommandInfo(CMD) = .getCommandInfo!(config, RemoveDefaultAttribute!CMD, RemoveDefaultAttribute!CMD.stringof);
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
        static foreach (name; info.names)
            static assert(name[0] != config.namedArgChar, TYPE.stringof~": Argument name should not begin with '"~config.namedArgChar~"': "~name);

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

package(argparse) Command createCommand(Config config, COMMAND_TYPE, CommandInfo info = getCommandInfo!(config, COMMAND_TYPE))(ref COMMAND_TYPE receiver)
{
    import std.algorithm: map;
    import std.array: array;

    alias typeTraits = TypeTraits!(config, COMMAND_TYPE);

    Command res;

    res.arguments.add!(config, COMMAND_TYPE, [typeTraits.argumentInfos]);
    res.restrictions.add!(config, COMMAND_TYPE, [typeTraits.argumentInfos]);

    res.parseFunctions = getArgumentParsingFunctions!(config, Command[], COMMAND_TYPE, typeTraits.argumentUDAs).map!(_ =>
        (const Command[] cmdStack, Config* config, string argName, string[] argValue)
            => _(cmdStack, config, receiver, argName, argValue)
        ).array;

    res.completeFunctions = getArgumentCompletionFunctions!(config, Command[], COMMAND_TYPE, typeTraits.argumentUDAs).map!(_ =>
        (const Command[] cmdStack, Config* config, string argName, string[] argValue)
            => _(cmdStack, config, receiver, argName, argValue)
        ).array;

    res.setTrailingArgs = (ref string[] args)
    {
        .setTrailingArgs(receiver, args);
    };

    res.info = info;

    res.subCommands.add([typeTraits.subCommandInfos]);

    static foreach(subcmd; typeTraits.subCommands)
    {{
        auto dg = () => ParsingSubCommandCreate!(config, subcmd.Type, subcmd.info, COMMAND_TYPE, typeTraits.subCommandSymbol)(receiver);

        static if(isDefaultCommand!(subcmd.Type))
            res.defaultSubCommand = dg;

        res.subCommandCreate ~= dg;
    }}

    return res;
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private auto ParsingSubCommandCreate(Config config, COMMAND_TYPE, CommandInfo info, RECEIVER, alias symbol)(ref RECEIVER receiver)
{
    auto target = &__traits(getMember, receiver, symbol);

    alias create = (ref COMMAND_TYPE actualTarget)
    {
        auto cmd = createCommand!(config, RemoveDefaultAttribute!COMMAND_TYPE, info)(actualTarget);
        cmd.isDefault = isDefaultCommand!COMMAND_TYPE;
        return cmd;
    };

    static if(typeof(*target).Types.length == 1)
        return (*target).match!create;
    else
    {
        // Initialize if needed
        if((*target).match!((ref COMMAND_TYPE t) => false, _ => true))
            *target = COMMAND_TYPE.init;

        return (*target).match!(create,
            (_)
            {
                assert(false, "This should never happen");
                return Command.init;
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
