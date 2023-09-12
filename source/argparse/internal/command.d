module argparse.internal.command;

import argparse.config;
import argparse.param;
import argparse.result;
import argparse.api.argument: TrailingArguments, NamedArgument, NumberOfValues;
import argparse.api.command: isDefaultCommand, RemoveDefaultAttribute, SubCommandsUDA = SubCommands;
import argparse.internal.arguments: Arguments, ArgumentInfo;
import argparse.internal.commandinfo;
import argparse.internal.argumentuda: ArgumentUDA, getArgumentUDA, getMemberArgumentUDA;
import argparse.internal.help: HelpArgumentUDA;

import std.typecons: Nullable, nullable;
import std.traits: getSymbolsByUDA, hasUDA, getUDAs;
import std.sumtype: match, isSumType;


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package struct SubCommands
{
    size_t[string] byName;

    CommandInfo[] info;


    void add(CommandInfo cmdInfo)()
    {
        immutable index = info.length;

        static foreach(name; cmdInfo.names)
        {{
            assert(!(name in byName), "Duplicated name of subcommand: "~name);
            byName[name] = index;
        }}

        info ~= cmdInfo;
    }
}


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private alias ParseFunction(COMMAND_STACK, RECEIVER) = Result delegate(const COMMAND_STACK cmdStack, ref RECEIVER receiver, string argName, string[] rawValues);

private alias ParsingArgument(Config config, COMMAND_STACK, RECEIVER, alias symbol, alias uda, bool completionMode) =
    delegate(const COMMAND_STACK cmdStack, ref RECEIVER receiver, string argName, string[] rawValues)
    {
        static if(completionMode)
        {
            return Result.Success;
        }
        else
        {
            try
            {
                auto res = uda.info.checkValuesCount!config(argName, rawValues.length);
                if(!res)
                    return res;

                immutable cfg = config;
                auto param = RawParam(&cfg, argName, rawValues);

                auto target = &__traits(getMember, receiver, symbol);

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
    };

unittest
{
    struct T { string a; }

    auto test(TYPE)(string[] values)
    {
        TYPE t;

        return ParsingArgument!(Config.init, string[], TYPE, "a", NamedArgument("arg-name").NumberOfValues(1), false)([], t, "arg-name", values);
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

    T t;

    auto res = ParsingArgument!(Config.init, string[], T, "func", NamedArgument("arg-name").NumberOfValues(0), false)([], t, "arg-name", []);

    assert(res.isError(Config.init.styling.argumentName("arg-name")~": My Message."));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package auto getArgumentParsingFunctions(Config config, COMMAND_STACK, TYPE, symbols...)()
{
    ParseFunction!(COMMAND_STACK, TYPE)[] res;

    static foreach(symbol; symbols)
        res ~= ParsingArgument!(config, COMMAND_STACK, TYPE, symbol, getMemberArgumentUDA!(config, TYPE, symbol, NamedArgument), false);

    return res;
}

package auto getArgumentCompletionFunctions(Config config, COMMAND_STACK, TYPE, symbols...)()
{
    ParseFunction!(COMMAND_STACK, TYPE)[] res;

    static foreach(symbol; symbols)
        res ~= ParsingArgument!(config, COMMAND_STACK, TYPE, symbol, getMemberArgumentUDA!(config, TYPE, symbol, NamedArgument), true);

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

    alias ParseFunction = Result delegate(const Command[] cmdStack, string argName, string[] argValue);
    ParseFunction[] parseFunctions;
    ParseFunction[] completeFunctions;

    Result parseArgument(const Command[] cmdStack, size_t argIndex, string argName, string[] argValue) const
    {
        return parseFunctions[argIndex](cmdStack, argName, argValue);
    }
    Result completeArgument(const Command[] cmdStack, size_t argIndex, string argName, string[] argValue) const
    {
        return completeFunctions[argIndex](cmdStack, argName, argValue);
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


    string displayName() const { return info.displayNames[0]; }
    Arguments arguments;

    CommandInfo info;

    SubCommands subCommands;
    Command delegate() pure nothrow [] subCommandCreate;
    Command delegate() pure nothrow defaultSubCommand;

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

    Result checkRestrictions(in bool[size_t] cliArgs) const
    {
        return arguments.checkRestrictions(cliArgs);
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

    template filter(alias sym)
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

package(argparse) Command createCommand(Config config, COMMAND_TYPE, CommandInfo info = getCommandInfo!(config, COMMAND_TYPE))(ref COMMAND_TYPE receiver)
{
    import std.algorithm: map;
    import std.array: array;
    import std.meta: Filter, staticMap, staticSort;


    enum hasArgumentUDA(alias sym) = hasUDA!(__traits(getMember, COMMAND_TYPE, sym), ArgumentUDA);
    enum getArgumentInfo(alias sym) = getMemberArgumentUDA!(config, COMMAND_TYPE, sym, void).info;//getUDAs!(__traits(getMember, COMMAND_TYPE, sym), ArgumentUDA)[0].info;

    enum positional(ArgumentInfo info) = info.positional;

    enum cmp(ArgumentInfo info1, ArgumentInfo info2) = info1.position.get - info2.position.get;

    enum positionalArgs = staticSort!(cmp, Filter!(positional, staticMap!(getArgumentInfo, Filter!(hasArgumentUDA, iterateArguments!COMMAND_TYPE))));

    static foreach(int i, info; positionalArgs)
    {{
        enum int pos = info.position.get;

        static if(i < pos)
            static assert(false, "Positional argument with index "~i.stringof~" is missed in "~COMMAND_TYPE.stringof);
        else static if(i > pos)
            static assert(false, "Positional argument with index "~pos.stringof~" is duplicated in "~COMMAND_TYPE.stringof);

        static if(pos < positionalArgs.length - 1)
            static assert(info.minValuesCount.get == info.maxValuesCount.get, "Positional argument with index "~pos.stringof~" in "~COMMAND_TYPE.stringof~" has variable number of values.");
    }}

    Command res;

    static foreach(symbol; iterateArguments!COMMAND_TYPE)
    {{
        enum uda = getMemberArgumentUDA!(config, COMMAND_TYPE, symbol, NamedArgument);

        static foreach(name; uda.info.names)
            static assert(name[0] != config.namedArgPrefix, "Argument name should not begin with '"~config.namedArgPrefix~"': "~name);

        res.arguments.addArgument!(config, COMMAND_TYPE, symbol, uda.info);
    }}

    res.parseFunctions = getArgumentParsingFunctions!(config, Command[], COMMAND_TYPE, iterateArguments!COMMAND_TYPE).map!(_ =>
        (const Command[] cmdStack, string argName, string[] argValue)
            => _(cmdStack, receiver, argName, argValue)
        ).array;

    res.completeFunctions = getArgumentCompletionFunctions!(config, Command[], COMMAND_TYPE, iterateArguments!COMMAND_TYPE).map!(_ =>
        (const Command[] cmdStack, string argName, string[] argValue)
            => _(cmdStack, receiver, argName, argValue)
        ).array;

    static if(config.addHelp)
    {{
        enum uda = getArgumentUDA!(Config.init, bool, null, HelpArgumentUDA());

        res.arguments.addArgument!(config, COMMAND_TYPE, null, uda.info);

        res.parseFunctions ~=
            (const Command[] cmdStack, string argName, string[] argValue)
                => uda.parsingFunc.parse!(config, COMMAND_TYPE)(cmdStack, receiver, argName, argValue);

        res.completeFunctions ~=
            (const Command[] cmdStack, string argName, string[] argValue)
                => Result.Success;
    }}

    res.setTrailingArgs = (ref string[] args)
    {
        .setTrailingArgs(receiver, args);
    };

    res.info = info;

    enum symbol = subCommandSymbol!COMMAND_TYPE;

    static if(symbol.length > 0)
    {
        static foreach(TYPE; typeof(__traits(getMember, COMMAND_TYPE, symbol)).Types)
        {{
            enum cmdInfo = getCommandInfo!(config, RemoveDefaultAttribute!TYPE, RemoveDefaultAttribute!TYPE.stringof);

            static if(isDefaultCommand!TYPE)
            {
                assert(res.defaultSubCommand is null, "Multiple default subcommands: "~COMMAND_TYPE.stringof~"."~symbol);
                res.defaultSubCommand = () => ParsingSubCommandCreate!(config, TYPE, cmdInfo, COMMAND_TYPE, symbol)()(receiver);
            }

            res.subCommands.add!cmdInfo;

            res.subCommandCreate ~= () => ParsingSubCommandCreate!(config, TYPE, cmdInfo, COMMAND_TYPE, symbol)()(receiver);
        }}
    }

    return res;
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private auto ParsingSubCommandCreate(Config config, COMMAND_TYPE, CommandInfo info, RECEIVER, alias symbol)()
{
    return function (ref RECEIVER receiver)
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
    };
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
