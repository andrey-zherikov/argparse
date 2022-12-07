module argparse.internal.parser;

import argparse.api: Config, Result;
import argparse.internal: commandArguments;
import argparse.internal.arguments: Arguments;
import argparse.internal.subcommands;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private string[] consumeValuesFromCLI(ref string[] args, ulong minValuesCount, ulong maxValuesCount, char namedArgChar)
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

package struct Parser
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

    Config* config;

    string[] args;
    string[] unrecognizedArgs;

    bool[size_t] idxParsedArgs;
    size_t idxNextPositional = 0;


    struct Command
    {
        Result delegate(ref Parser parser, const Command[] cmdStack, const ref Command command, const ref Argument) parse;
        Result delegate(ref Parser parser, const Command[] cmdStack, const ref Command command, const ref Argument) complete;
        bool isDefault;

        Arguments.FindResult delegate(string name) findNamedArgument;
        Arguments.FindResult delegate(size_t position) findPositionalArgument;

        Result delegate(const Command[] cmdStack, Config* config, size_t argIndex, string argName, string[] argValue) parseArgument;
        Result delegate(const Command[] cmdStack, Config* config, size_t argIndex, string argName, string[] argValue) completeArgument;

        void delegate(ref string[] args) setTrailingArgs;

        Command delegate(const Command[] cmdStack, const ref Command command, string name) getSubCommand;

        string[] delegate(string prefix) suggestions;


        string displayName;
        Arguments arguments;

        static Command create(Config config, COMMAND, RECEIVER)(ref COMMAND cmd, ref RECEIVER receiver)
        {
            Command res;
            res.parse = (ref Parser parser, const Command[] cmdStack, const ref Command command, const ref arg)
                {
                    return parser.parse!false(cmdStack, command, arg);
                };
            res.complete = (ref Parser parser, const Command[] cmdStack, const ref Command command, const ref arg)
                {
                    return parser.parse!true(cmdStack, command, arg);
                };
            res.findNamedArgument = (string name)
                {
                    return cmd.arguments.findNamedArgument(name);
                };
            res.findPositionalArgument = (size_t position)
                {
                    return cmd.arguments.findPositionalArgument(position);
                };
            res.parseArgument = (const Command[] cmdStack, Config* config, size_t argIndex, string argName, string[] argValue)
                {
                    return cmd.getParseFunction!false(argIndex)(cmdStack, config, cmd, receiver, argName, argValue);
                };
            res.completeArgument = (const Command[] cmdStack, Config* config, size_t argIndex, string argName, string[] argValue)
                {
                    return cmd.getParseFunction!true(argIndex)(cmdStack, config, cmd, receiver, argName, argValue);
                };
            res.setTrailingArgs = (ref string[] args)
                {
                    cmd.setTrailingArgs(receiver, args);
                };
            res.getSubCommand = (const Command[] cmdStack, const ref Command parentCommand, string name)
                {
                    auto found = cmd.findSubCommand(name);
                    if(found.parse is null)
                        return Command.init;

                    found.initialize(receiver);

                    auto ccc = found.createCommand(receiver);

                    Command res = ccc;
                    res.parse = (ref Parser parser, const Command[] cmdStack, const ref Command command, const ref arg)
                        {
                            //return ccc.parse(parser, ccc, arg);
                            //return parser.parse!false(ccc, arg);
                            //return parser.parse!false(command, arg);
                            auto c = found.parse(parser, cmdStack, arg, receiver);
                            return c;//parser.parse!false(c, arg);
                        };
                    res.complete = (ref Parser parser, const Command[] cmdStack, const ref Command command, const ref arg)
                        {
                            auto c = found.complete(parser, cmdStack, arg, receiver);
                            return c;//parser.parse!true(c, arg);
                        };
                    res.isDefault = name == DEFAULT_COMMAND;

                    return res;
                };
            res.arguments = cmd.arguments;
            res.displayName = cmd.info.displayNames[0];

            res.suggestions = (string prefix)
                {
                    import std.range: chain;
                    import std.algorithm: filter, map;
                    import std.string: startsWith;
                    import std.array: array, join;

                    // suggestions are names of all arguments and subcommands
                    auto suggestions = chain(cmd.arguments.arguments.map!(_ => _.displayNames).join, cmd.subCommands.byName.keys);

                    // empty prefix means that we need to provide all suggestions, otherwise they are filtered
                    return prefix == "" ? suggestions.array : suggestions.filter!(_ => _.startsWith(prefix)).array;
                };

            return res;
        }
    }
    Command[] cmdStack;


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
        ? Argument(NamedLong (config.convertCase(nameWithDash[2..$]), nameWithDash, value))
        : Argument(NamedShort(config.convertCase(nameWithDash[1..$]), nameWithDash, value));
    }

    auto parseArgument(bool completionMode, FOUNDARG)(const Command[] cmdStack, const ref Command cmd, FOUNDARG foundArg, string value, string nameWithDash)
    {
        scope(exit) idxParsedArgs[foundArg.index] = true;

        auto rawValues = value !is null ? [value] : consumeValuesFromCLI(args, foundArg.arg.minValuesCount.get, foundArg.arg.maxValuesCount.get, config.namedArgChar);

        static if(completionMode)
            return cmd.completeArgument(cmdStack, config, foundArg.index, nameWithDash, rawValues);
        else
            return cmd.parseArgument(cmdStack, config, foundArg.index, nameWithDash, rawValues);
    }

    auto parseSubCommand(const Command[] cmdStack1, const ref Command cmd)
    {
        import std.range: front, popFront;

        auto subcmd = cmd.getSubCommand(cmdStack, cmd, config.convertCase(args.front));
        if(subcmd.parse is null)
            return Result.UnknownArgument;

        if(cmdStack1.length < cmdStack.length)
            cmdStack.length = cmdStack1.length;

        addCommand(subcmd, false);

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

        auto res = parseArgument!completionMode(cmdStack, cmd, foundArg, null, foundArg.arg.names[0]);
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
        return parseArgument!completionMode(cmdStack, cmd, foundArg, arg.value, arg.nameWithDash);
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
            return parseArgument!completionMode(cmdStack, cmd, foundArg, arg.value, arg.nameWithDash);
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

            auto res = parseArgument!completionMode(cmdStack, cmd, foundArg, value, "-"~name);
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
            static if(completionMode)
            {
                auto res = cmdParser.complete(this, cmdStack1, cmdParser, arg);
                if(res)
                    result.suggestions ~= res.suggestions;
            }
            else
            {
                auto res = cmdParser.parse(this, cmdStack1, cmdParser, arg);

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

    auto parseAll(bool completionMode, COMMAND)(const ref COMMAND cmd)
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
                    return res;
        }

        return cmd.checkRestrictions(idxParsedArgs, config);
    }

    void addCommand(Command cmd, bool addDefaultCommand)
    {
        cmdStack ~= cmd;


        if(addDefaultCommand)
        {
            cmd = cmd.getSubCommand(cmdStack, cmd, DEFAULT_COMMAND);
            if (cmd.parse !is null)
            {
                cmdStack ~= cmd;

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

package(argparse) static Result callParser(Config origConfig, bool completionMode, COMMAND)(ref COMMAND receiver, string[] args, out string[] unrecognizedArgs)
{
    import argparse.ansi: detectSupport;

    auto config = origConfig;
    config.setStylingModeHandlers ~= (Config.StylingMode mode) { config.stylingMode = mode; };

    auto parser = Parser(&config, args);

    auto command = commandArguments!(origConfig, COMMAND);

    parser.addCommand(Parser.Command.create!origConfig(command, receiver), true);

    auto res = parser.parseAll!completionMode(command);

    static if(!completionMode)
    {
        if(res)
        {
            unrecognizedArgs = parser.unrecognizedArgs;

            if(config.stylingMode == Config.StylingMode.autodetect)
                config.setStylingMode(detectSupport() ? Config.StylingMode.on : Config.StylingMode.off);

            command.onParsingDone(receiver, &config);
        }
        else if(res.errorMsg.length > 0)
            config.onError(res.errorMsg);
    }

    return res;
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////