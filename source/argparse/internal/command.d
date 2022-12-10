module argparse.internal.command;

import std.typecons: Nullable, nullable;
import std.traits: getSymbolsByUDA;

import argparse.api: Config, Result, RemoveDefault, TrailingArguments;
import argparse.internal: commandArguments;
import argparse.internal.arguments: Arguments;
import argparse.internal.subcommands: DEFAULT_COMMAND, CommandInfo, getCommandInfo;

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
    Command delegate()[] subCommandCreate;

    auto getSubCommand(const Command[] cmdStack, string name) const
    {
        auto pIndex = name in subCommandByName;
        if(pIndex is null)
            return Nullable!Command.init;

        auto subCmd = subCommandCreate[*pIndex]();
        subCmd.isDefault = name == DEFAULT_COMMAND;

        return nullable(subCmd);
    }

    void delegate(const Config* config)[] parseFinalizers;

    void onParsingDone(const Config* config) const
    {
        foreach(dg; parseFinalizers)
            dg(config);
    }

    Result checkRestrictions(in bool[size_t] cliArgs, Config* config) const
    {
        return arguments.checkRestrictions(cliArgs, config);
    }


    static Command create(Config config, COMMAND_TYPE, CommandInfo info = getCommandInfo!(config, COMMAND_TYPE))(ref COMMAND_TYPE receiver)
    {
        auto cmd = commandArguments!(config, COMMAND_TYPE, info);

        import std.algorithm: map;
        import std.array: array;

        Command res;

        res.parseFunctions = cmd.parseArguments.map!(_ =>
            (const Command[] cmdStack, Config* config, string argName, string[] argValue)
        => _(cmdStack, config, receiver, argName, argValue)
        ).array;
        res.completeFunctions = cmd.completeArguments.map!(_ =>
            (const Command[] cmdStack, Config* config, string argName, string[] argValue)
        => _(cmdStack, config, receiver, argName, argValue)
        ).array;
        res.subCommandCreate = cmd.subCommands.createFunc.map!(_ =>
            () => _(receiver),
        ).array;
        res.parseFinalizers = cmd.parseFinalizers.map!(_ =>
            (const Config* config) => _(receiver, config),
        ).array;

        res.setTrailingArgs = (ref string[] args)
        {
            .setTrailingArgs(receiver, args);
        };

        res.info = cmd.info;
        res.arguments = cmd.arguments;
        res.subCommandInfos = cmd.subCommands.info;
        res.subCommandByName = cmd.subCommands.byName;

        return res;
    }
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