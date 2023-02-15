module argparse.internal.command;

import std.typecons: Nullable, nullable;
import std.traits: getSymbolsByUDA;

import argparse.config;
import argparse.result;
import argparse: NamedArgument;
import argparse.api: RemoveDefault, TrailingArguments;
import argparse.internal: iterateArguments;
import argparse.internal.arguments: Arguments;
import argparse.internal.commandinfo;
import argparse.internal.subcommands: DEFAULT_COMMAND, createSubCommands;
import argparse.internal.hooks: HookHandlers;
import argparse.internal.argumentparser;
import argparse.internal.argumentuda: getArgumentUDA, getMemberArgumentUDA;
import argparse.internal.help: HelpArgumentUDA;

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
        auto suggestions_ = chain(arguments.arguments.map!(_ => _.displayNames).join, subCommandByName.keys);

        // empty prefix means that we need to provide all suggestions, otherwise they are filtered
        return prefix == "" ? suggestions_.array : suggestions_.filter!(_ => _.startsWith(prefix)).array;
    }


    string displayName() const { return info.displayNames[0]; }
    Arguments arguments;

    CommandInfo info;

    size_t[string] subCommandByName;
    CommandInfo[] subCommandInfos;
    Command delegate() pure nothrow [] subCommandCreate;

    auto getSubCommand(const Command[] cmdStack, string name) const
    {
        auto pIndex = name in subCommandByName;
        if(pIndex is null)
            return Nullable!Command.init;

        auto subCmd = subCommandCreate[*pIndex]();
        subCmd.isDefault = name == DEFAULT_COMMAND;

        return nullable(subCmd);
    }

    HookHandlers hooks;

    void onParsingDone(const Config* config) const
    {
        hooks.onParsingDone(config);
    }

    Result checkRestrictions(in bool[size_t] cliArgs, Config* config) const
    {
        return arguments.checkRestrictions(cliArgs, config);
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) Command createCommand(Config config, COMMAND_TYPE, CommandInfo info = getCommandInfo!(config, COMMAND_TYPE))(ref COMMAND_TYPE receiver)
{
    import std.algorithm: map;
    import std.array: array;

    Command res;

    static foreach(symbol; iterateArguments!COMMAND_TYPE)
    {{
        enum uda = getMemberArgumentUDA!(config, COMMAND_TYPE, symbol, NamedArgument);

        res.arguments.addArgument!(COMMAND_TYPE, symbol, uda.info);
    }}

    res.parseFunctions = getArgumentParsingFunctions!(config, Command[], COMMAND_TYPE, iterateArguments!COMMAND_TYPE).map!(_ =>
        (const Command[] cmdStack, Config* config, string argName, string[] argValue)
            => _(cmdStack, config, receiver, argName, argValue)
        ).array;

    res.completeFunctions = getArgumentCompletionFunctions!(config, Command[], COMMAND_TYPE, iterateArguments!COMMAND_TYPE).map!(_ =>
        (const Command[] cmdStack, Config* config, string argName, string[] argValue)
            => _(cmdStack, config, receiver, argName, argValue)
        ).array;

    static if(config.addHelp)
    {{
        enum uda = getArgumentUDA!(Config.init, bool, null, HelpArgumentUDA());

        res.arguments.addArgument!(COMMAND_TYPE, null, uda.info);

        res.parseFunctions ~=
            (const Command[] cmdStack, Config* config, string argName, string[] argValue)
                => uda.parsingFunc.parse!COMMAND_TYPE(cmdStack, config, receiver, argName, argValue);

        res.completeFunctions ~=
            (const Command[] cmdStack, Config* config, string argName, string[] argValue)
                => Result.Success;
    }}

    res.hooks.bind!(COMMAND_TYPE, iterateArguments!COMMAND_TYPE)(receiver);

    res.setTrailingArgs = (ref string[] args)
    {
        .setTrailingArgs(receiver, args);
    };

    res.info = info;

    enum subCommands = createSubCommands!(config, COMMAND_TYPE);

    res.subCommandInfos = subCommands.info;
    res.subCommandByName = subCommands.byName;
    res.subCommandCreate = subCommands.createFunc.map!(_ => () => _(receiver)).array;


    return res;
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private void setTrailingArgs(RECEIVER)(ref RECEIVER receiver, ref string[] rawArgs)
{
    alias ORIG_TYPE = RemoveDefault!RECEIVER;

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
