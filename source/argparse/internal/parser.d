module argparse.internal.parser;

import std.typecons: Nullable, nullable;
import std.sumtype: SumType;

import argparse.config;
import argparse.result;
import argparse.api.ansi: ansiStylingArgument;
import argparse.api.command: Default, SubCommands;
import argparse.internal.arguments: ArgumentInfo;
import argparse.internal.command: Command, createCommand;
import argparse.internal.commandinfo: getTopLevelCommandInfo;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private string[] consumeValuesFromCLI(Config config, ref string[] args,
                                      ulong minValuesCount, ulong maxValuesCount,
                                      bool delegate(string) isCommand)
{
    import std.range: empty, front, popFront;

    string[] values;
    values.reserve(minValuesCount);

    // consume minimum number of values
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

    // consume up to maximum number of values
    while(!args.empty &&
        values.length < maxValuesCount &&
        args.front != config.endOfArgs &&
        !isCommand(args.front) &&
        !(args.front.length > 0 && args.front[0] == config.namedArgPrefix))
    {
        values ~= args.front;
        args.popFront();
    }

    return values;
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
private string[] splitSingleLetterNames(string arg)
{
    // Split "-ABC" into ["-A","-B","-C"]
    import std.array: array;
    import std.algorithm: map;
    import std.conv: to;

    char prefix = arg[0];

    return arg[1..$].map!(_ => [prefix, _].to!string).array;
}
private string[] splitSingleLetterNames(string arg, char assignChar, string value)
{
    // Split "-ABC=<value>" into ["-A","-B","-C=<value>"]

    auto res = splitSingleLetterNames(arg);

    // append value to the last argument
    res[$-1] ~= assignChar ~ value;

    return res;
}

unittest
{
    assert(splitSingleLetterNames("-a") == ["-a"]);
    assert(splitSingleLetterNames("-abc") == ["-a","-b","-c"]);
    assert(splitSingleLetterNames("-a",'=',"") == ["-a="]);
    assert(splitSingleLetterNames("-a",'=',"value") == ["-a=value"]);
    assert(splitSingleLetterNames("-abc",'=',"") == ["-a","-b","-c="]);
    assert(splitSingleLetterNames("-abc",'=',"value") == ["-a","-b","-c=value"]);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
struct Unknown {
    string value;
}
struct EndOfArgs {
    string[] args;
}
struct Argument {
    size_t index;
    const(ArgumentInfo)* info;
    Result delegate() parse;
    Result delegate() complete;

    this(string name, FindResult r, string[] values)
    {
        index = r.arg.index;
        info = r.arg.info;

        parse = () => r.arg.parse(r.cmdStack, name, values);
        complete = () => r.arg.complete(r.cmdStack, name, values);
    }
}
struct SubCommand {
    Command delegate() cmdInit;
}

alias Entry = SumType!(Unknown, EndOfArgs, Argument, SubCommand);

private Entry getNextEntry(bool bundling)(Config config, ref string[] args,
                                          FindResult delegate(bool) findPositionalArg,
                                          FindResult delegate(string) findNamedArg,
                                          Command delegate() delegate(string) findCommand)
{
    import std.range: popFront;

    assert(args.length > 0);

    auto arg0 = args[0];

    if(arg0.length == 0)
    {
        args.popFront;
        return Entry(Unknown(arg0));
    }

    // Is it "--"?
    if(arg0 == config.endOfArgs)
    {
        scope(success) args = [];            // nothing else left to parse
        return Entry(EndOfArgs(args[1..$])); // skip "--"
    }

    // Is it named argument (starting with '-' and longer than 1 character)?
    if(arg0[0] == config.namedArgPrefix && arg0.length > 1)
    {
        import std.string : indexOf;
        import std.algorithm : startsWith;

        // Is it a long name ("--...")?
        if(arg0[1] == config.namedArgPrefix)
        {
            // cases (from higher to lower priority):
            //  --foo=val    => --foo val
            //  --abc ...    => --abc ...
            //  --no-abc     => --abc false       < only for boolean flags

            // Look for assign character
            immutable idxAssignChar = config.assignChar == char.init ? -1 : arg0.indexOf(config.assignChar);
            if(idxAssignChar > 0)
            {
                // "--<arg>=<value>" case
                immutable usedName = arg0[0 .. idxAssignChar];
                immutable value    = arg0[idxAssignChar + 1 .. $];
                immutable argName  = config.convertCase(usedName[2..$]);     // 2 to remove "--" prefix

                auto res = findNamedArg(argName);
                if(res.arg)
                {
                    args.popFront;
                    return Entry(Argument(usedName, res, [value]));
                }
            }
            else
            {
                // Just "--<arg>"
                immutable argName = config.convertCase(arg0[2..$]);     // 2 to remove "--" prefix

                {
                    auto res = findNamedArg(argName);
                    if (res.arg)
                    {
                        args.popFront;
                        auto values = consumeValuesFromCLI(config, args, res.arg.info.minValuesCount.get, res.arg.info.maxValuesCount.get, n => (findCommand(n) !is null));
                        return Entry(Argument(arg0, res, values));
                    }
                }

                if(argName.startsWith(config.convertCase("no-")))
                {
                    // It is a boolean flag specified as "--no-<arg>"
                    auto res = findNamedArg(argName[3..$]);    // remove "no-" prefix
                    if(res.arg && res.arg.info.isBooleanFlag)
                    {
                        args.popFront;
                        return Entry(Argument(arg0, res, ["false"]));
                    }
                }
            }
        }
        else
        {
            // It is a short name: "-..."

            // cases (from higher to lower priority):
            //  -foo=val    => -foo val             < similar to "--..."
            //  -abc=val    => -a -b -c=val         < only if config.bundling is true
            //  -abc        => -abc                 < similar to "--..."
            //              => -a bc
            //              => -a -b -c             < only if config.bundling is true

            // Look for assign character
            immutable idxAssignChar = config.assignChar == char.init ? -1 : arg0.indexOf(config.assignChar);
            if(idxAssignChar > 0)
            {
                // "-<arg>=<value>" case
                auto usedName = arg0[0 .. idxAssignChar];
                auto value    = arg0[idxAssignChar + 1 .. $];
                auto argName  = config.convertCase(usedName[1..$]);     // 1 to remove "-" prefix

                {
                    auto res = findNamedArg(argName);
                    if (res.arg)
                    {
                        args.popFront;
                        return Entry(Argument(usedName, res, [value]));
                    }
                }

                static if(bundling)
                    if(argName.length > 1)     // Ensure that there is something to split
                    {
                        // Try to process "-ABC=<value>" case where "A","B","C" are single-letter arguments
                        // The above example is equivalent to ["-A","-B","-C=<value>"]

                        // Look for the first argument ("-A" from the example above)
                        auto res = findNamedArg([argName[0]]);
                        if(res.arg)
                        {
                            // We don't need first argument because we've already got it
                            auto restArgs = splitSingleLetterNames(usedName, config.assignChar, value)[1..$];

                            // Replace first element with set of single-letter arguments
                            args = restArgs ~ args[1..$];

                            // Due to bundling argument has no value
                            return Entry(Argument(usedName[0..2], res, []));
                        }
                    }
            }
            else
            {
                // Just "-<arg>"
                immutable argName = config.convertCase(arg0[1..$]);     // 1 to remove "-" prefix

                {
                    auto res = findNamedArg(argName);
                    if (res.arg)
                    {
                        args.popFront;
                        auto values = consumeValuesFromCLI(config, args, res.arg.info.minValuesCount.get, res.arg.info.maxValuesCount.get, n => (findCommand(n) !is null));
                        return Entry(Argument(arg0, res, values));
                    }
                }

                if(argName.length > 1)     // Ensure that there is something to split
                {
                    // Try to process "-ABC" case where "A" is a single-letter argument

                    // Look for the first argument ("-A" from the example above)
                    auto res = findNamedArg([argName[0]]);
                    if(res.arg)
                    {
                        // If argument accepts at least one value then the rest is that value
                        if(res.arg.info.minValuesCount.get > 0)
                        {
                            auto value = arg0[2..$];
                            args.popFront;
                            return Entry(Argument(arg0[0..2], res, [value]));
                        }

                        static if(bundling)
                        {
                            // Process "ABC" as "-A","-B","-C"

                            // We don't need first argument because we've already got it
                            auto restArgs = splitSingleLetterNames(arg0)[1..$];

                            // Replace first element with set of single-letter arguments
                            args = restArgs ~ args[1..$];

                            // Due to bundling argument has no value
                            return Entry(Argument(arg0[0..2], res, []));
                        }
                    }
                }
            }
        }
    }
    else
    {
        // Check for required positional argument in the current command
        auto res = findPositionalArg(true);
        if(res.arg && res.arg.info.required)
        {
            auto values = consumeValuesFromCLI(config, args, res.arg.info.minValuesCount.get, res.arg.info.maxValuesCount.get, n => (findCommand(n) !is null));
            return Entry(Argument(res.arg.info.placeholder, res, values));
        }

        // Is it sub command?
        auto cmdInit = findCommand(arg0);
        if(cmdInit !is null)
        {
            args.popFront;
            return Entry(SubCommand(cmdInit));
        }

        // Check for optional positional argument in the current command
        if(res.arg)
        {
            auto values = consumeValuesFromCLI(config, args, res.arg.info.minValuesCount.get, res.arg.info.maxValuesCount.get, n => (findCommand(n) !is null));
            return Entry(Argument(res.arg.info.placeholder, res, values));
        }

        // Check for positional argument in sub commands
        res = findPositionalArg(false);
        if(res.arg)
        {
            auto values = consumeValuesFromCLI(config, args, res.arg.info.minValuesCount.get, res.arg.info.maxValuesCount.get, n => (findCommand(n) !is null));
            return Entry(Argument(res.arg.info.placeholder, res, values));
        }
    }

    args.popFront;
    return Entry(Unknown(arg0));
}

unittest
{
    auto test(string[] args) { return getNextEntry!false(Config.init, args, null, null, null); }

    assert(test([""]) == Entry(Unknown("")));
    assert(test(["--","a","-b","c"]) == Entry(EndOfArgs(["a","-b","c"])));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private auto findCommand(ref Command[] cmdStack, string name)
{
    import std.range: back;

    // Look up in comand stack
    foreach_reverse(ref cmd; cmdStack)
    {
        auto res = cmd.getSubCommand(name);
        if(res)
            return res;
    }
    // Look up through default subcommands
    for(auto stack = cmdStack[]; stack.back.defaultSubCommand !is null;)
    {
        stack ~= stack.back.defaultSubCommand();

        auto res = stack.back.getSubCommand(name);
        if(res)
        {
            // update stack
            cmdStack = stack;

            return res;
        }
    }
    return null;
}

private struct FindResult
{
    Command.Argument arg;

    const(Command)[] cmdStack;
}

private FindResult findArgument(ref Command[] cmdStack, string name)
{
    import std.range: back, popBack;

    // Look up in command stack
    for(auto stack = cmdStack[]; stack.length > 0; stack.popBack)
    {
        auto res = stack.back.findNamedArgument(name);
        if(res)
            return FindResult(res, stack);
    }

    // Look up through default subcommands
    for(auto stack = cmdStack[]; stack.back.defaultSubCommand !is null;)
    {
        stack ~= stack.back.defaultSubCommand();

        auto res = stack.back.findNamedArgument(name);
        if(res)
        {
            // update stack
            cmdStack = stack;

            return FindResult(res, stack);
        }
    }

    return FindResult.init;
}

private FindResult findArgument(ref Command[] cmdStack, ref size_t[] idxPositionalStack, size_t position, bool currentStackOnly)
{
    import std.range: back;

    if(currentStackOnly)
    {
        // Look up in current command stack
        // Actual stack can be longer than the one we looked up through last time
        // because parsing of named argument can add default commands into it
        for(auto stackSize = idxPositionalStack.length; stackSize <= cmdStack.length; ++stackSize)
        {
            if(idxPositionalStack.length < stackSize)
                idxPositionalStack ~= position;

            auto stack = cmdStack[0..stackSize];

            auto res = stack.back.findPositionalArgument(position - idxPositionalStack[$-1]);
            if(res)
                return FindResult(res, stack);
        }
    }
    else
    {
        for(auto stack = cmdStack[], posStack = idxPositionalStack; stack.back.defaultSubCommand !is null;)
        {
            stack ~= stack.back.defaultSubCommand();
            posStack ~= position;

            auto res = stack.back.findPositionalArgument(0);  // position is always 0 in new sub command
            if(res)
            {
                // update stack
                cmdStack = stack;
                idxPositionalStack = posStack;

                return FindResult(res, stack);
            }
        }
    }
    return FindResult.init;
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private struct Parser
{
    Config config;
    string[] unrecognizedArgs;

    bool[size_t] idxParsedArgs;


    size_t idxNextPositional = 0;

    size_t[] idxPositionalStack;
    Command[] cmdStack;

    invariant(cmdStack.length >= idxPositionalStack.length);

    ///////////////////////////////////////////////////////////////////////

    auto parse(Argument a, Result delegate() parseFunc)
    {
        auto res = parseFunc();
        if(!res)
            return res;

        idxParsedArgs[a.index] = true;

        if(a.info.positional)
            idxNextPositional++;

        return Result.Success;
    }
    auto parse(EndOfArgs)
    {
        return Result.Success;
    }
    auto parse(SubCommand subcmd)
    {
        addCommand(subcmd.cmdInit());

        return Result.Success;
    }
    auto parse(Unknown u)
    {
        unrecognizedArgs ~= u.value;

        return Result.Success;
    }

    ///////////////////////////////////////////////////////////////////////

    auto parseAll(bool completionMode, bool bundling)(string[] args)
    {
        import std.range: empty, join;
        import std.sumtype : match;
        import std.algorithm : map;

        while(!args.empty)
        {
            static if(completionMode)
            {
                if(args.length > 1)
                {
                    auto res = getNextEntry!bundling(
                            config, args,
                            _ => findArgument(cmdStack, idxPositionalStack, idxNextPositional, _),
                            _ => findArgument(cmdStack, _),
                            _ => findCommand(cmdStack, _),
                        )
                        .match!(
                            (Argument a) => parse(a, a.complete),
                            _ => parse(_));
                    if (!res)
                        return res;
                }
                else
                {
                    // Provide suggestions for the last argument only
                    auto res = Result.Success;
                    res.suggestions = cmdStack.map!((ref _) => _.suggestions(args[0])).join;
                    return res;
                }
            }
            else
            {
                auto res = getNextEntry!bundling(
                        config, args,
                        _ => findArgument(cmdStack, idxPositionalStack, idxNextPositional, _),
                        _ => findArgument(cmdStack, _),
                        _ => findCommand(cmdStack, _),
                    )
                    .match!(
                        (Argument a) => parse(a, a.parse),
                        (EndOfArgs e)
                        {
                            import std.range: back;

                            cmdStack.back.setTrailingArgs(e.args);
                            unrecognizedArgs ~= e.args;

                            return parse(e);
                        },
                        _ => parse(_)
                    );
                if (!res)
                    return res;
            }
        }

        return cmdStack[0].checkRestrictions(idxParsedArgs);
    }

    void addCommand(Command cmd)
    {
        cmdStack ~= cmd;
        idxPositionalStack ~= idxNextPositional;
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private Result callParser(bool completionMode, bool bundling)(
    Config config, Command cmd, string[] args, out string[] unrecognizedArgs,
)
{
    ansiStylingArgument.isEnabled = config.stylingMode == Config.StylingMode.on;

    Parser parser = { config };
    parser.addCommand(cmd);

    auto res = parser.parseAll!(completionMode, bundling)(args);

    static if(!completionMode)
    {
        if(res)
            unrecognizedArgs = parser.unrecognizedArgs;
    }

    return res;
}

package(argparse) Result callParser(Config config, bool completionMode, COMMAND)(ref COMMAND receiver, string[] args, out string[] unrecognizedArgs)
if(config.stylingMode != Config.StylingMode.autodetect)
{
    return callParser!(completionMode, config.bundling)(
        config, createCommand!config(receiver, getTopLevelCommandInfo!COMMAND(config)), args, unrecognizedArgs,
    );
}

private auto enableStyling(Config config, bool enable)
{
    config.stylingMode = enable ? Config.StylingMode.on : Config.StylingMode.off;
    return config;
}

unittest
{
    assert(enableStyling(Config.init, true).stylingMode == Config.StylingMode.on);
    assert(enableStyling(Config.init, false).stylingMode == Config.StylingMode.off);
}

package(argparse) Result callParser(Config config, bool completionMode, COMMAND)(ref COMMAND receiver, string[] args, out string[] unrecognizedArgs)
if(config.stylingMode == Config.StylingMode.autodetect)
{
    import argparse.ansi: detectSupport;


    if(detectSupport())
        return callParser!(enableStyling(config, true), completionMode, COMMAND)(receiver, args, unrecognizedArgs);
    else
        return callParser!(enableStyling(config, false), completionMode, COMMAND)(receiver, args, unrecognizedArgs);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
unittest
{
    import argparse.api.argument: PositionalArgument, NamedArgument;

    struct T
    {
        @NamedArgument bool c;
        @PositionalArgument(0) string fileName;
    }

    {
        T t;
        string[] unrecognizedArgs;
        assert(callParser!(enableStyling(Config.init, false), false)(t, ["-", "-c"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(t == T(true, "-"));
    }
    {
        T t;
        string[] unrecognizedArgs;
        assert(callParser!(enableStyling(Config.init, false), false)(t, ["-c", "-"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(t == T(true, "-"));
    }
    {
        T t;
        string[] unrecognizedArgs;
        assert(callParser!(enableStyling(Config.init, false), false)(t, ["-"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(t == T(false, "-"));
    }
    {
        T t;
        string[] unrecognizedArgs;
        assert(callParser!(enableStyling(Config.init, false), false)(t, ["-f","-"], unrecognizedArgs));
        assert(unrecognizedArgs == ["-f"]);
        assert(t == T(false, "-"));
    }
}
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

unittest
{
    struct c1 {
        string foo;
        string boo;
    }
    struct cmd {
        string foo;
        SumType!(c1) c;
    }

    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(enableStyling(Config.init, false), false)(c, ["--foo","FOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO"));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(enableStyling(Config.init, false), false)(c, ["--boo","BOO"], unrecognizedArgs));
        assert(unrecognizedArgs == ["--boo","BOO"]);
        assert(c == cmd.init);
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(enableStyling(Config.init, false), false)(c, ["--foo","FOO","--boo","BOO"], unrecognizedArgs));
        assert(unrecognizedArgs == ["--boo","BOO"]);
        assert(c == cmd("FOO"));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(enableStyling(Config.init, false), false)(c, ["--boo","BOO","--foo","FOO"], unrecognizedArgs));
        assert(unrecognizedArgs == ["--boo","BOO"]);
        assert(c == cmd("FOO"));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(enableStyling(Config.init, false), false)(c, ["c1","--boo","BOO","--foo","FOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("", typeof(c.c)(c1("FOO","BOO"))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(enableStyling(Config.init, false), false)(c, ["--foo","FOO","c1","--boo","BOO","--foo","FAA"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1("FAA","BOO"))));
    }
}

unittest
{
    struct c1 {
        string foo;
        string boo;
    }
    struct cmd {
        string foo;
        SumType!(Default!c1) c;
    }

    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(enableStyling(Config.init, false), false)(c, ["--foo","FOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO"));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(enableStyling(Config.init, false), false)(c, ["--boo","BOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("", typeof(c.c)(Default!c1(c1("","BOO")))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(enableStyling(Config.init, false), false)(c, ["--foo","FOO","--boo","BOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(Default!c1(c1("","BOO")))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(enableStyling(Config.init, false), false)(c, ["--boo","BOO","--foo","FOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("", typeof(c.c)(Default!c1(c1("FOO","BOO")))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(enableStyling(Config.init, false), false)(c, ["c1","--boo","BOO","--foo","FOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("", typeof(c.c)(Default!c1(c1("FOO","BOO")))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(enableStyling(Config.init, false), false)(c, ["--foo","FOO","c1","--boo","BOO","--foo","FAA"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(Default!c1(c1("FAA","BOO")))));
    }
}


unittest
{
    import argparse.api.argument: PositionalArgument;

    struct c1 {
        @PositionalArgument(0)
        string foo;
        @PositionalArgument(1)
        string boo;
    }
    struct cmd {
        @PositionalArgument(0)
        string foo;
        @SubCommands
        SumType!(c1) c;
    }

    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(enableStyling(Config.init, false), false)(c, ["FOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO"));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(enableStyling(Config.init, false), false)(c, ["FOO","FAA"], unrecognizedArgs));
        assert(unrecognizedArgs == ["FAA"]);
        assert(c == cmd("FOO"));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(enableStyling(Config.init, false), false)(c, ["FOO","FAA","BOO"], unrecognizedArgs));
        assert(unrecognizedArgs == ["FAA","BOO"]);
        assert(c == cmd("FOO"));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(enableStyling(Config.init, false), false)(c, ["c1","FOO"], unrecognizedArgs));
        assert(unrecognizedArgs == ["FOO"]);
        assert(c == cmd("c1"));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(enableStyling(Config.init, false), false)(c, ["FOO","c1","FAA"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1("FAA"))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(enableStyling(Config.init, false), false)(c, ["FOO","c1","FAA","BOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1("FAA","BOO"))));
    }
}


unittest
{
    import argparse.api.argument: PositionalArgument;

    struct c1 {
        @PositionalArgument(0)
        string foo;
        @PositionalArgument(1)
        string boo;
    }
    struct cmd {
        @PositionalArgument(0)
        string foo;
        @SubCommands
        SumType!(Default!c1) c;
    }

    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(enableStyling(Config.init, false), false)(c, ["FOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO"));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(enableStyling(Config.init, false), false)(c, ["FOO","FAA"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(Default!c1(c1("FAA")))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(enableStyling(Config.init, false), false)(c, ["FOO","FAA","BOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(Default!c1(c1("FAA","BOO")))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(enableStyling(Config.init, false), false)(c, ["c1","FOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("c1", typeof(c.c)(Default!c1(c1("FOO")))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(enableStyling(Config.init, false), false)(c, ["FOO","c1","FAA"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(Default!c1(c1("FAA")))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(enableStyling(Config.init, false), false)(c, ["FOO","c1","FAA","BOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(Default!c1(c1("FAA","BOO")))));
    }
}


unittest
{
    import argparse.api.argument: PositionalArgument, NamedArgument;

    struct c2 {
        @PositionalArgument(0)
        string foo;
        @PositionalArgument(1)
        string boo;
        @NamedArgument
        string bar;
    }
    struct c1 {
        @PositionalArgument(0)
        string foo;
        @PositionalArgument(1)
        string boo;
        @SubCommands
        SumType!(Default!c2) c;
    }
    struct cmd {
        @PositionalArgument(0)
        string foo;
        @SubCommands
        SumType!(Default!c1) c;
    }

    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(enableStyling(Config.init, false), false)(c, ["FOO","FAA","BOO","FEE","BEE"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(Default!c1(c1("FAA","BOO", typeof(c1.c)(Default!c2(c2("FEE","BEE"))))))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(enableStyling(Config.init, false), false)(c, ["--bar","BAR","FOO","FAA","BOO","FEE","BEE"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(Default!c1(c1("FAA","BOO", typeof(c1.c)(Default!c2(c2("FEE","BEE","BAR"))))))));
    }
}


unittest
{
    import argparse.api.argument: PositionalArgument, NamedArgument;

    struct c2 {
        @PositionalArgument(0)
        string foo;
        @PositionalArgument(1)
        string boo;
        @NamedArgument
        string bar;
    }
    struct c1 {
        @SubCommands
        SumType!(Default!c2) c;
    }
    struct cmd {
        @PositionalArgument(0)
        string foo;
        @SubCommands
        SumType!(Default!c1) c;
    }

    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(enableStyling(Config.init, false), false)(c, ["FOO","FAA","BOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(Default!c1(c1(typeof(c1.c)(Default!c2(c2("FAA","BOO"))))))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(enableStyling(Config.init, false), false)(c, ["--bar","BAR","FOO","FAA","BOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(Default!c1(c1(typeof(c1.c)(Default!c2(c2("FAA","BOO","BAR"))))))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(enableStyling(Config.init, false), false)(c, ["FOO","c2","FAA","BOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(Default!c1(c1(typeof(c1.c)(Default!c2(c2("FAA","BOO"))))))));
    }
}