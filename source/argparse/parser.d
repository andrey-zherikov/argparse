module argparse.parser;

import argparse;
import argparse.internal;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package struct Parser
{
    import std.sumtype: SumType;

    struct Unknown {}
    struct EndOfArgs {}
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

    alias Argument = SumType!(Unknown, EndOfArgs, Positional, NamedShort, NamedLong);

    Config* config;

    string[] args;
    string[] unrecognizedArgs;

    bool[size_t] idxParsedArgs;
    size_t idxNextPositional = 0;

    struct CmdParser
    {
        Result delegate(const ref Argument) parse;
        Result delegate(const ref Argument) complete;
        const(string)[] completeSuggestion;
        bool isDefault;
    }
    CmdParser[] cmdStack;

    Argument splitArgumentNameValue(string arg)
    {
        import std.string : indexOf;

        if(arg.length == 0)
            return Argument.init;

        if(arg == config.endOfArgs)
            return Argument(EndOfArgs.init);

        if(arg[0] != config.namedArgChar)
            return Argument(Positional.init);

        if(arg.length == 1 || arg.length == 2 && arg[1] == config.namedArgChar)
            return Argument.init;

        auto idxAssignChar = config.assignChar == char.init ? -1 : arg.indexOf(config.assignChar);

        immutable string nameWithDash = idxAssignChar < 0 ? arg  : arg[0 .. idxAssignChar];
        immutable string value        = idxAssignChar < 0 ? null : arg[idxAssignChar + 1 .. $];

        return arg[1] == config.namedArgChar
        ? Argument(NamedLong (nameWithDash[2..$], nameWithDash, value))
        : Argument(NamedShort(nameWithDash[1..$], nameWithDash, value));
    }

    auto parseArgument(T, PARSE)(PARSE parse, ref T receiver, string value, string nameWithDash, size_t argIndex)
    {
        auto res = parse(config, nameWithDash, receiver, value, args);
        if(!res)
            return res;

        idxParsedArgs[argIndex] = true;

        return Result.Success;
    }

    auto parseSubCommand(T)(const ref CommandArguments!T cmd, ref T receiver)
    {
        import std.range: front, popFront;

        auto found = cmd.findSubCommand(args.front);
        if(found.parse is null)
            return Result.UnknownArgument;

        if(found.level < cmdStack.length)
            cmdStack.length = found.level;

        cmdStack ~= CmdParser((const ref arg) => found.parse(config, this, arg, false, receiver), (const ref arg) => found.complete(config, this, arg, false, receiver));

        found.initialize(receiver);
        args.popFront();

        return Result.Success;
    }

    auto parse(bool completionMode, T)(const ref CommandArguments!T cmd, bool isDefaultCmd, ref T receiver, Unknown)
    {
        static if(completionMode)
        {
            import std.range: front, popFront;
            import std.algorithm: filter;
            import std.string:startsWith;
            import std.array:array;
            if(args.length == 1)
            {
                // last arg means we need to provide args and subcommands
                auto A = args[0] == "" ? cmd.completeSuggestion : cmd.completeSuggestion.filter!(_ => _.startsWith(args[0])).array;
                return Result(0, Result.Status.success, "", A);
            }
        }

        return Result.UnknownArgument;
    }

    auto parse(bool completionMode, T)(const ref CommandArguments!T cmd, bool isDefaultCmd, ref T receiver, EndOfArgs)
    {
        static if(!completionMode)
        {
            import std.range: popFront;

            args.popFront();

            cmd.setTrailingArgs(receiver, args);
            unrecognizedArgs ~= args;
        }

        args = [];

        return Result.Success;
    }

    auto parse(bool completionMode, T)(const ref CommandArguments!T cmd, bool isDefaultCmd, ref T receiver, Positional)
    {
        auto foundArg = cmd.findPositionalArgument(idxNextPositional);
        if(foundArg.arg is null)
            return parseSubCommand(cmd, receiver);

        auto res = parseArgument(cmd.getParseFunction!completionMode(foundArg.index), receiver, null, foundArg.arg.names[0], foundArg.index);
        if(!res)
            return res;

        idxNextPositional++;

        return Result.Success;
    }

    auto parse(bool completionMode, T)(const ref CommandArguments!T cmd, bool isDefaultCmd, ref T receiver, NamedLong arg)
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

        if(isDefaultCmd && foundArg.arg.ignoreInDefaultCommand)
            return Result.UnknownArgument;

        args.popFront();
        return parseArgument(cmd.getParseFunction!completionMode(foundArg.index), receiver, arg.value, arg.nameWithDash, foundArg.index);
    }

    auto parse(bool completionMode, T)(const ref CommandArguments!T cmd, bool isDefaultCmd, ref T receiver, NamedShort arg)
    {
        import std.range: popFront;

        auto foundArg = cmd.findNamedArgument(arg.name);
        if(foundArg.arg !is null)
        {
            if(isDefaultCmd && foundArg.arg.ignoreInDefaultCommand)
                return Result.UnknownArgument;

            args.popFront();
            return parseArgument(cmd.getParseFunction!completionMode(foundArg.index), receiver, arg.value, arg.nameWithDash, foundArg.index);
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

            auto res = parseArgument(cmd.getParseFunction!completionMode(foundArg.index), receiver, value, "-"~name, foundArg.index);
            if(!res)
                return res;
        }
        while(arg.name.length > 0);

        args.popFront();
        return Result.Success;
    }

    auto parse(bool completionMode, T)(const ref CommandArguments!T cmd, bool isDefaultCmd, ref T receiver, Argument arg)
    {
        import std.sumtype: match;

        return arg.match!(_ => parse!completionMode(cmd, isDefaultCmd, receiver, _));
    }

    auto parse(bool completionMode)(Argument arg)
    {
        import std.range: front, popFront;

        auto result = Result.Success;

        const argsCount = args.length;

        foreach_reverse(cmdParser; cmdStack)
        {
            static if(completionMode)
            {
                auto res = cmdParser.complete(arg);
                if(res)
                    result.suggestions ~= res.suggestions;
            }
            else
            {
                auto res = cmdParser.parse(arg);

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

    auto parseAll(bool completionMode, T)(const ref CommandArguments!T cmd, ref T receiver)
    {
        import std.range: empty, front;

        cmdStack ~= CmdParser(
        (const ref arg)
        {
            return parse!completionMode(cmd, false, receiver, arg);
        },
        (const ref arg)
        {
            return parse!completionMode(cmd, false, receiver, arg);
        },
        cmd.completeSuggestion);

        auto found = cmd.findSubCommand(DEFAULT_COMMAND);
        if(found.parse !is null)
        {
            auto p = CmdParser((const ref arg) => found.parse(config, this, arg, true, receiver));
            p.isDefault = true;
            cmdStack ~= p;
            found.initialize(receiver);
        }

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
                    return res;
        }

        return cmd.checkRestrictions(idxParsedArgs, config);
    }
}

unittest
{
    Config config;
    assert(Parser(&config).splitArgumentNameValue("") == Parser.Argument(Parser.Unknown.init));
    assert(Parser(&config).splitArgumentNameValue("-") == Parser.Argument(Parser.Unknown.init));
    assert(Parser(&config).splitArgumentNameValue("--") == Parser.Argument(Parser.EndOfArgs.init));
    assert(Parser(&config).splitArgumentNameValue("abc=4") == Parser.Argument(Parser.Positional.init));
    assert(Parser(&config).splitArgumentNameValue("-abc") == Parser.Argument(Parser.NamedShort("abc", "-abc", null)));
    assert(Parser(&config).splitArgumentNameValue("--abc") == Parser.Argument(Parser.NamedLong("abc", "--abc", null)));
    assert(Parser(&config).splitArgumentNameValue("-abc=fd") == Parser.Argument(Parser.NamedShort("abc", "-abc", "fd")));
    assert(Parser(&config).splitArgumentNameValue("--abc=fd") == Parser.Argument(Parser.NamedLong("abc", "--abc", "fd")));
    assert(Parser(&config).splitArgumentNameValue("-abc=") == Parser.Argument(Parser.NamedShort("abc", "-abc", "")));
    assert(Parser(&config).splitArgumentNameValue("--abc=") == Parser.Argument(Parser.NamedLong("abc", "--abc", "")));
    assert(Parser(&config).splitArgumentNameValue("-=abc") == Parser.Argument(Parser.NamedShort("", "-", "abc")));
    assert(Parser(&config).splitArgumentNameValue("--=abc") == Parser.Argument(Parser.NamedLong("", "--", "abc")));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package static Result callParser(Config origConfig, bool completionMode, COMMAND)(ref COMMAND receiver, string[] args, out string[] unrecognizedArgs)
{
    import argparse.ansi: detectSupport;

    auto config = origConfig;
    config.setStylingModeHandlers ~= (Config.StylingMode mode) { config.helpStylingMode = mode; };

    auto parser = Parser(&config, args);

    auto command = CommandArguments!COMMAND(&config);
    auto res = parser.parseAll!completionMode(command, receiver);

    static if(!completionMode)
    {
        if(res)
        {
            unrecognizedArgs = parser.unrecognizedArgs;

            if(config.helpStylingMode == Config.StylingMode.autodetect)
                config.setStylingMode(detectSupport() ? Config.StylingMode.on : Config.StylingMode.off);

            command.onParsingDone(receiver, &config);
        }
        else if(res.errorMsg.length > 0)
            config.onError(res.errorMsg);
    }

    return res;
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////