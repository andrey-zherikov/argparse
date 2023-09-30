module argparse.internal.parser;

import std.typecons: Nullable, nullable;

import argparse.config;
import argparse.result;
import argparse.api.ansi: ansiStylingArgument;
import argparse.internal.arguments: Arguments;
import argparse.internal.command: Command, createCommand;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private string[] consumeValuesFromCLI(ref string[] args, ulong minValuesCount, ulong maxValuesCount, char namedArgPrefix)
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
        (args.front.length == 0 || args.front[0] != namedArgPrefix))
    {
        values ~= args.front;
        args.popFront();
    }

    return values;
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private struct Parser(Config config)
{
    import std.sumtype: SumType;

    struct Unknown {}
    struct EndOfArgs {}
    struct Positional {}
    struct NamedShort {
        string name;
        string nameWithDash;
        string value = null;  // null when there is no "=value"
    }
    struct NamedLong {
        string name;
        string nameWithDash;
        string value = null;  // null when there is no "=value"
    }

    alias Argument = SumType!(Unknown, EndOfArgs, Positional, NamedShort, NamedLong);

    string[] args;
    string[] unrecognizedArgs;

    bool[size_t] idxParsedArgs;
    size_t idxNextPositional = 0;


    Command[] cmdStack;


    static Argument splitArgumentNameValue(string arg)
    {
        import std.string : indexOf;

        if(arg.length == 0)
            return Argument.init;

        if(arg == config.endOfArgs)
            return Argument(EndOfArgs.init);

        if(arg[0] != config.namedArgPrefix)
            return Argument(Positional.init);

        if(arg.length == 1 || arg.length == 2 && arg[1] == config.namedArgPrefix)
            return Argument.init;

        auto idxAssignChar = config.assignChar == char.init ? -1 : arg.indexOf(config.assignChar);

        immutable string nameWithDash = idxAssignChar < 0 ? arg  : arg[0 .. idxAssignChar];
        immutable string value        = idxAssignChar < 0 ? null : arg[idxAssignChar + 1 .. $];

        return arg[1] == config.namedArgPrefix
        ? Argument(NamedLong (config.convertCase(nameWithDash[2..$]), nameWithDash, value))
        : Argument(NamedShort(config.convertCase(nameWithDash[1..$]), nameWithDash, value));
    }

    auto parseArgument(FOUNDARG)(const Command[] cmdStack, const ref Command cmd, FOUNDARG foundArg, string value, string nameWithDash)
    {
        scope(exit) idxParsedArgs[foundArg.index] = true;

        auto rawValues = value !is null ? [value] : consumeValuesFromCLI(args, foundArg.arg.minValuesCount.get, foundArg.arg.maxValuesCount.get, config.namedArgPrefix);

        return cmd.parseArgument(cmdStack, foundArg.index, nameWithDash, rawValues);
    }

    auto parseSubCommand(const Command[] cmdStack1, const ref Command cmd)
    {
        import std.range: front, popFront;

        auto subcmd = cmd.getSubCommand(cmdStack, config.convertCase(args.front));
        if(subcmd.isNull)
            return Result.UnknownArgument;

        if(cmdStack1.length < cmdStack.length)
            cmdStack.length = cmdStack1.length;

        addCommand(subcmd.get, false);

        args.popFront();

        return Result.Success;
    }

    auto parse(bool completionMode)(const Command[] cmdStack, const ref Command cmd, Unknown)
    {
        static if(completionMode)
        {
            if(args.length == 1)
                return Result(0, Result.Status.success, "", cmd.suggestions(args[0]));
        }

        return Result.UnknownArgument;
    }

    auto parse(bool completionMode)(const Command[] cmdStack, const ref Command cmd, EndOfArgs)
    {
        static if(!completionMode)
        {
            import std.range: popFront;

            args.popFront(); // remove "--"

            cmd.setTrailingArgs(args);
            unrecognizedArgs ~= args;
        }

        args = [];

        return Result.Success;
    }

    auto parse(bool completionMode)(const Command[] cmdStack, const ref Command cmd, Positional)
    {
        auto foundArg = cmd.findPositionalArgument(idxNextPositional);
        if(foundArg.arg is null)
            return parseSubCommand(cmdStack, cmd);

        auto res = parseArgument(cmdStack, cmd, foundArg, null, foundArg.arg.placeholder);
        if(!res)
            return res;

        idxNextPositional++;

        return Result.Success;
    }

    auto parse(bool completionMode)(const Command[] cmdStack, const ref Command cmd, NamedLong arg)
    {
        import std.algorithm : startsWith;
        import std.range: popFront;

        auto foundArg = cmd.findNamedArgument(arg.name);

        if(foundArg.arg is null && arg.name.startsWith("no-"))
        {
            foundArg = cmd.findNamedArgument(arg.name[3..$]);
            if(foundArg.arg is null || !foundArg.arg.allowBooleanNegation)
                return Result.UnknownArgument;

            arg.value = "false";
        }

        if(foundArg.arg is null)
            return Result.UnknownArgument;

        if(cmd.isDefault && foundArg.arg.ignoreInDefaultCommand)
            return Result.UnknownArgument;

        args.popFront();
        return parseArgument(cmdStack, cmd, foundArg, arg.value, arg.nameWithDash);
    }

    auto parse(bool completionMode)(const Command[] cmdStack, const ref Command cmd, NamedShort arg)
    {
        import std.range: popFront;

        auto foundArg = cmd.findNamedArgument(arg.name);
        if(foundArg.arg !is null)
        {
            if(cmd.isDefault && foundArg.arg.ignoreInDefaultCommand)
                return Result.UnknownArgument;

            args.popFront();
            return parseArgument(cmdStack, cmd, foundArg, arg.value, arg.nameWithDash);
        }

        // Try to parse "-ABC..." where "A","B","C" are different single-letter arguments
        do
        {
            auto name = [arg.name[0]];
            foundArg = cmd.findNamedArgument(name);
            if(foundArg.arg is null)
                return Result.UnknownArgument;

            // In case of bundling there can be no or one argument value
            if(config.bundling && foundArg.arg.minValuesCount.get > 1)
                return Result.UnknownArgument;

            // In case of NO bundling there MUST be one argument value
            if(!config.bundling && foundArg.arg.minValuesCount.get != 1)
                return Result.UnknownArgument;

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

            auto res = parseArgument(cmdStack, cmd, foundArg, value, "-"~name);
            if(!res)
                return res;
        }
        while(arg.name.length > 0);

        args.popFront();
        return Result.Success;
    }

    auto parse(bool completionMode)(const Command[] cmdStack, const ref Command cmd, Argument arg)
    {
        import std.sumtype: match;

        return arg.match!(_ => parse!completionMode(cmdStack, cmd, _));
    }

    auto parse(bool completionMode)(Argument arg)
    {
        import std.range: front, popFront, popBack, back;

        auto result = Result.Success;

        const argsCount = args.length;

        foreach_reverse(index, cmdParser; cmdStack)
        {
            auto cmdStack1 = cmdStack[0..index+1];

            static if(completionMode)
            {
                auto res = parse!true(cmdStack1, cmdParser, arg);

                if(res)
                    result.suggestions ~= res.suggestions;
            }
            else
            {
                auto res = parse!false(cmdStack1, cmdParser, arg);

                if(res.status != Result.Status.unknownArgument)
                    return res;
            }
        }

        if(args.length > 0 && argsCount == args.length)
        {
            unrecognizedArgs ~= args.front;
            args.popFront();
        }

        return result;
    }

    auto parseAll(bool completionMode)()
    {
        import std.range: empty, front, back;

        while(!args.empty)
        {
            static if(completionMode)
                auto res = parse!completionMode(args.length > 1 ? splitArgumentNameValue(args.front) : Argument.init);
            else
                auto res = parse!completionMode(splitArgumentNameValue(args.front));
            if(!res)
                return res;

            static if(completionMode)
                if(args.empty)
                    return res; // res contains suggestions
        }

        return cmdStack[0].checkRestrictions(idxParsedArgs);
    }

    void addCommand(Command cmd, bool addDefaultCommand)
    {
        cmdStack ~= cmd;


        if(addDefaultCommand)
        {
            auto subcmd = cmd.getDefaultSubCommand(cmdStack);
            if(!subcmd.isNull)
            {
                cmdStack ~= subcmd.get;

                //import std.stdio : writeln, stderr;stderr.writeln("-- addCommand 1 ", cmd.getSubCommand);
                //
                //cmd = cmd.getSubCommand(DEFAULT_COMMAND);
                //import std.stdio : writeln, stderr;stderr.writeln("-- addCommand 2 ", cmd);
            }
        }
        //do
        //{
        //    cmd = cmd.getSubCommand(DEFAULT_COMMAND);
        //    if(cmd.parse !is null)
        //        cmdStack ~= cmd;
        //}
        //while(cmd.parse !is null);
    }
}

unittest
{
    alias P = Parser!(Config.init);
    assert(P.splitArgumentNameValue("") == P.Argument(P.Unknown.init));
    assert(P.splitArgumentNameValue("-") == P.Argument(P.Unknown.init));
    assert(P.splitArgumentNameValue("--") == P.Argument(P.EndOfArgs.init));
    assert(P.splitArgumentNameValue("abc=4") == P.Argument(P.Positional.init));
    assert(P.splitArgumentNameValue("-abc") == P.Argument(P.NamedShort("abc", "-abc", null)));
    assert(P.splitArgumentNameValue("--abc") == P.Argument(P.NamedLong("abc", "--abc", null)));
    assert(P.splitArgumentNameValue("-abc=fd") == P.Argument(P.NamedShort("abc", "-abc", "fd")));
    assert(P.splitArgumentNameValue("--abc=fd") == P.Argument(P.NamedLong("abc", "--abc", "fd")));
    assert(P.splitArgumentNameValue("-abc=") == P.Argument(P.NamedShort("abc", "-abc", "")));
    assert(P.splitArgumentNameValue("--abc=") == P.Argument(P.NamedLong("abc", "--abc", "")));
    assert(P.splitArgumentNameValue("-=abc") == P.Argument(P.NamedShort("", "-", "abc")));
    assert(P.splitArgumentNameValue("--=abc") == P.Argument(P.NamedLong("", "--", "abc")));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) Result callParser(Config config, bool completionMode, COMMAND)(ref COMMAND receiver, string[] args, out string[] unrecognizedArgs)
if(config.stylingMode != Config.StylingMode.autodetect)
{
    ansiStylingArgument.isEnabled = config.stylingMode == Config.StylingMode.on;

    auto parser = Parser!config(args);

    auto cmd = createCommand!(config, COMMAND)(receiver);
    parser.addCommand(cmd, true);

    auto res = parser.parseAll!completionMode;

    static if(!completionMode)
    {
        if(res)
            unrecognizedArgs = parser.unrecognizedArgs;
    }

    return res;
}

private auto enableStyling(Config config)(bool enable)
{
    Config c = config;
    c.stylingMode = enable ? Config.StylingMode.on : Config.StylingMode.off;
    return c;
}

unittest
{
    assert(enableStyling!(Config.init)(true).stylingMode == Config.StylingMode.on);
    assert(enableStyling!(Config.init)(false).stylingMode == Config.StylingMode.off);
}

package(argparse) Result callParser(Config config, bool completionMode, COMMAND)(ref COMMAND receiver, string[] args, out string[] unrecognizedArgs)
if(config.stylingMode == Config.StylingMode.autodetect)
{
    import argparse.ansi: detectSupport;


    if(detectSupport())
        return callParser!(enableStyling!config(true), completionMode, COMMAND)(receiver, args, unrecognizedArgs);
    else
        return callParser!(enableStyling!config(false), completionMode, COMMAND)(receiver, args, unrecognizedArgs);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////