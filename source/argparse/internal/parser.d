module argparse.internal.parser;

import std.typecons: Nullable, nullable;
import std.sumtype: SumType;

import argparse.config;
import argparse.param;
import argparse.result;
import argparse.api.ansi: ansiStylingArgument;
import argparse.internal.arguments: ArgumentInfo;
import argparse.internal.command: Command, createCommand;
import argparse.internal.commandinfo: getTopLevelCommandInfo;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private string[] consumeValuesFromCLI(ref string[] args,
                                      size_t minValuesCount, size_t maxValuesCount,
                                      bool delegate(string) isArgumentValue)
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
    while(!args.empty && values.length < maxValuesCount && isArgumentValue(args.front))
    {
        values ~= args.front;
        args.popFront();
    }

    return values;
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package string[] splitValues(string value, char valueSep, const(ArgumentInfo)* info)
{
    import std.array: split;

    return value.length > 0 && info.maxValuesCount.get > 1 ? value.split(valueSep) : [value];
}

unittest
{
    ArgumentInfo info = { maxValuesCount: 2 };
    assert(splitValues("", ',', &info) == [""]);
    assert(splitValues("abc", ',', &info) == ["abc"]);
    assert(splitValues("a,b,c", ',', &info) == ["a","b","c"]);
    assert(splitValues("a b c", ' ', &info) == ["a","b","c"]);
    assert(splitValues("a,b,c", ' ', &info) == ["a,b,c"]);
    assert(splitValues("a,b,c", char.init, &info) == ["a,b,c"]);
}

unittest
{
    ArgumentInfo info = { maxValuesCount: 1 };
    assert(splitValues("", ',', &info) == [""]);
    assert(splitValues("abc", ',', &info) == ["abc"]);
    assert(splitValues("a,b,c", ',', &info) == ["a,b,c"]);
    assert(splitValues("a b c", ' ', &info) == ["a b c"]);
    assert(splitValues("a,b,c", ' ', &info) == ["a,b,c"]);
    assert(splitValues("a,b,c", char.init, &info) == ["a,b,c"]);
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

private struct Unknown {
    string value;
}

private struct Argument {
    const(ArgumentInfo)* info;
    Result delegate() parse;
    Result delegate() complete;

    this(RawParam param, FindResult r)
    {
        info = r.arg.info;

        parse = () => r.arg.parse(r.cmdStack, param);
        complete = () => r.arg.complete(r.cmdStack, param);
    }
}

private struct SubCommand {
    Command delegate() cmdInit;
}

private alias Entry = SumType!(Unknown, Argument, SubCommand);

private Entry getNextEntry(const ref Config config, ref string[] args,
                           FindResult delegate(bool) findPositionalArg,
                           FindResult delegate(string) findShortNamedArg,
                           FindResult delegate(string) findLongNamedArg,
                           Command delegate() delegate(string) findCommand)
{
    import std.algorithm : startsWith, min;
    import std.range: popFront;
    import std.string : indexOf;

    assert(args.length > 0);

    const arg0 = args[0];

    if(arg0.length == 0)
    {
        args.popFront;
        return Entry(Unknown(arg0));
    }

    auto isArgumentValue = (string str)
    {
        return str.length == 0 ||                           // empty string is a value
               str != config.endOfNamedArgs &&              // `--` is not a value
               !str.startsWith(config.shortNamePrefix) &&   // short name is not a value
               !str.startsWith(config.longNamePrefix) &&    // long name is not a value
               findCommand(str) is null;                    // command is not a value
    };

    auto createArgument = (string name, string[] values, FindResult res) => Entry(Argument(RawParam(&config, name, values), res));

    // Is it a long name ("--...")?
    if(arg0.length > config.longNamePrefix.length && arg0.startsWith(config.longNamePrefix))
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
            immutable argName  = usedName[2..$];     // 2 to remove "--" prefix

            auto res = findLongNamedArg(argName);
            if(res.arg)
            {
                args.popFront;
                return createArgument(usedName, splitValues(value, config.valueSep, res.arg.info), res);
            }
        }
        else
        {
            // Just "--<arg>"
            immutable argName = arg0[2..$];     // 2 to remove "--" prefix

            {
                auto res = findLongNamedArg(argName);
                if (res.arg)
                {
                    args.popFront;
                    auto values = consumeValuesFromCLI(args,
                                                       res.arg.info.minValuesCount.get,
                                                       config.atMostOneValuePerNamedArg ? min(1, res.arg.info.maxValuesCount.get) : res.arg.info.maxValuesCount.get,
                                                       isArgumentValue);
                    return createArgument(arg0, values, res);
                }
            }

            if(argName.startsWith("no-"))
            {
                // It is a boolean flag specified as "--no-<arg>"
                auto res = findShortNamedArg(argName[3..$]);    // remove "no-" prefix

                if(!res.arg || !res.arg.info.isBooleanFlag)
                    res = findLongNamedArg(argName[3..$]);    // remove "no-" prefix

                if(res.arg && res.arg.info.isBooleanFlag)
                {
                    args.popFront;
                    return createArgument(arg0, ["false"], res);
                }
            }
        }
    }
    else if(arg0.length > config.shortNamePrefix.length && arg0.startsWith(config.shortNamePrefix))
    {
        // It is a short name: "-..."

        // cases (from higher to lower priority):
        //  -foo=val    => -foo val             < similar to "--..."
        //  -abc=val    => -a -b -c=val         < only if config.bundling is true
        //  -abcval     => -a -b -c val         < only if config.bundling is true
        //  -abc        => -abc                 < similar to "--..."
        //              => -a bc
        //              => -a -b -c             < only if config.bundling is true

        // First we will try o match whole argument name, then will try bundling

        // Look for assign character
        immutable idxAssignChar = config.assignChar == char.init ? -1 : arg0.indexOf(config.assignChar);
        if(idxAssignChar > 0)
        {
            // "-<arg>=<value>" case
            auto usedName = arg0[0 .. idxAssignChar];
            auto value    = arg0[idxAssignChar + 1 .. $];
            auto argName  = usedName[1..$];     // 1 to remove "-" prefix

            {
                auto res = findShortNamedArg(argName);
                if (res.arg)
                {
                    args.popFront;
                    return createArgument(usedName, splitValues(value, config.valueSep, res.arg.info), res);
                }
            }
        }
        else
        {
            // Just "-<arg>"
            immutable argName = arg0[1..$];     // 1 to remove "-" prefix

            {
                auto res = findShortNamedArg(argName);
                if (res.arg)
                {
                    args.popFront;
                    auto values = consumeValuesFromCLI(args,
                                                       res.arg.info.minValuesCount.get,
                                                       config.atMostOneValuePerNamedArg ? min(1, res.arg.info.maxValuesCount.get) : res.arg.info.maxValuesCount.get,
                                                       isArgumentValue);
                    return createArgument(arg0, values, res);
                }
            }

            // Try to process "-ABC" case where "A" is a single-character argument and BC is a value
            if(argName.length > 1)     // Ensure that there is something to split
            {
                // Look for the first argument ("-A" from the example above)
                auto res = findShortNamedArg([argName[0]]);
                if(res.arg)
                {
                    // If argument accepts at least one value then the rest is that value
                    if(res.arg.info.minValuesCount.get > 0)
                    {
                        auto value = arg0[2..$];
                        args.popFront;
                        return createArgument(arg0[0..2], [value], res);
                    }
                }
            }
        }

        if(config.bundling)
            if(arg0.length >= 3 && arg0[2] != config.assignChar)  // At least -AB and not -A=...
            {
                // Process "-ABC" as "-A","-BC": extract first character and leave the rest

                // Look for the first argument ("-A" from the example above)
                auto res = findShortNamedArg([arg0[1]]);
                if(res.arg)
                {
                    // Drop first character
                    auto rest = arg0[0]~arg0[2..$];// splitSingleLetterNames(usedName, config.assignChar, value)[1..$];

                    // Replace first element with the rest
                    args[0] = rest;

                    // Due to bundling argument has no value
                    return createArgument(arg0[0..2], [], res);
                }
            }
    }
    else
    {
        // Check for required positional argument in the current command
        {
            auto res = findPositionalArg(true);
            if (res.arg && res.arg.info.required)
            {
                auto values = consumeValuesFromCLI(args, res.arg.info.minValuesCount.get, res.arg.info.maxValuesCount.get, isArgumentValue);
                return createArgument(res.arg.info.placeholder, values, res);
            }

            // Is it sub command?
            auto cmdInit = findCommand(arg0);
            if (cmdInit !is null)
            {
                args.popFront;
                return Entry(SubCommand(cmdInit));
            }

            // Check for optional positional argument in the current command
            if (res.arg)
            {
                auto values = consumeValuesFromCLI(args, res.arg.info.minValuesCount.get, res.arg.info.maxValuesCount.get, isArgumentValue);
                return createArgument(res.arg.info.placeholder, values, res);
            }
        }

        // Check for positional argument in sub commands
        {
            auto res = findPositionalArg(false);
            if (res.arg)
            {
                auto values = consumeValuesFromCLI(args, res.arg.info.minValuesCount.get, res.arg.info.maxValuesCount.get, isArgumentValue);
                return createArgument(res.arg.info.placeholder, values, res);
            }
        }
    }

    args.popFront;
    return Entry(Unknown(arg0));
}

private Entry getNextPositionalArgument(const ref Config config, ref string[] args,
                                        FindResult delegate(bool) findPositionalArg)
{
    import std.range : popFront;

    assert(args.length > 0);

    auto createEntry(FindResult res)
    {
        auto values = consumeValuesFromCLI(args, res.arg.info.minValuesCount.get, res.arg.info.maxValuesCount.get, _ => true);
        return Entry(Argument(RawParam(&config, res.arg.info.placeholder, values), res));
    }

    // Check for positional argument in the current command
    {
        auto res = findPositionalArg(true);
        if(res.arg)
            return createEntry(res);
    }

    // Check for positional argument in sub commands
    {
        auto res = findPositionalArg(false);
        if(res.arg)
            return createEntry(res);
    }

    const arg0 = args[0];
    args.popFront;
    return Entry(Unknown(arg0));
}

unittest
{
    Config config = { bundling: false };
    auto args = [""];

    assert(getNextEntry(config, args, null, null, null, null) == Entry(Unknown("")));
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

    Command[] cmdStack;
}

private FindResult findArgument(ref Command[] cmdStack, Command.Argument delegate(ref Command) findNamedArgument)
{
    import std.range: back, popBack;

    // Look up in command stack
    for(auto stack = cmdStack[]; stack.length > 0; stack.popBack)
    {
        auto res = findNamedArgument(stack.back);
        if(res)
            return FindResult(res, stack);
    }

    // Look up through default subcommands
    for(auto stack = cmdStack[]; stack.back.defaultSubCommand !is null;)
    {
        stack ~= stack.back.defaultSubCommand();

        auto res = findNamedArgument(stack.back);
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

    size_t idxNextPositional = 0;

    size_t[] idxPositionalStack;
    Command[] cmdStack;

    invariant(cmdStack.length >= idxPositionalStack.length);

    ///////////////////////////////////////////////////////////////////////

    auto parse(Argument a, Result res)
    {
        if(!res)
            return res;

        if(a.info.positional)
            idxNextPositional++;

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

    auto parseAll(bool completionMode)(string[] args)
    {
        import std.range: empty, join;
        import std.sumtype : match;
        import std.algorithm : map;

        auto findPositionalArgument = (bool currentStackOnly) => findArgument(cmdStack, idxPositionalStack, idxNextPositional, currentStackOnly);
        auto getNext = () =>
            getNextEntry(config, args,
                findPositionalArgument,
                name => findArgument(cmdStack, (ref cmd) => cmd.findShortNamedArgument(name)),
                name => findArgument(cmdStack, (ref cmd) => cmd.findLongNamedArgument(name)),
                name => findCommand(cmdStack, name)
            );


        while(!args.empty)
        {
            // Is it "--"?
            if(args[0] == config.endOfNamedArgs)
            {
                args = args[1..$];
                getNext = () => getNextPositionalArgument(config, args, findPositionalArgument);
                continue;// to check for args.empty
            }

            static if(completionMode)
            {
                if(args.length > 1)
                {
                    auto res = getNext()
                        .match!(
                            (Argument a) => parse(a, Result.Success),
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
                auto res = getNext()
                    .match!(
                        (Argument a) => parse(a, a.parse()),
                        _ => parse(_)
                    );
                if (!res)
                    return res;
            }
        }
        foreach(ref cmd; cmdStack)
        {
            auto res = cmd.checkRestrictions();
            if(!res)
                return res;
        }

        return Result.Success;
    }

    void addCommand(Command cmd)
    {
        cmdStack ~= cmd;
        idxPositionalStack ~= idxNextPositional;
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private Result callParser(bool completionMode)(
    Config config, Command cmd, string[] args, out string[] unrecognizedArgs,
)
{
    ansiStylingArgument.isEnabled = config.stylingMode == Config.StylingMode.on;

    Parser parser = { config };
    parser.addCommand(cmd);

    auto res = parser.parseAll!completionMode(args);

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
    return callParser!completionMode(
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
    import argparse.api.argument;

    struct T
    {
        @(NamedArgument.NumberOfValues(2,4)) string[] f;
    }

    {
        enum Config config = { atMostOneValuePerNamedArg: false };

        T t;
        string[] unrecognizedArgs;
        assert(callParser!(config, false)(t, ["-f", "a"], unrecognizedArgs).isError("Argument", "expected at least 2 values"));
        assert(callParser!(config, false)(t, ["-f", "a", "a"], unrecognizedArgs));
        assert(callParser!(config, false)(t, ["-f", "a", "a", "a"], unrecognizedArgs));
        assert(callParser!(config, false)(t, ["-f", "a", "a", "a", "a"], unrecognizedArgs));

        assert(unrecognizedArgs.length == 0);
        assert(callParser!(config, false)(t, ["-f", "a", "a", "a", "a", "a"], unrecognizedArgs));
        assert(unrecognizedArgs == ["a"]);
    }
    {
        T t;
        string[] unrecognizedArgs;
        assert(callParser!(Config.init, false)(t, ["-f=a,a"], unrecognizedArgs));
        assert(callParser!(Config.init, false)(t, ["-f=a,a,a"], unrecognizedArgs));
        assert(callParser!(Config.init, false)(t, ["-f=a,a,a,a"], unrecognizedArgs));
        assert(callParser!(Config.init, false)(t, ["-f=a,a,a,a,a"], unrecognizedArgs).isError("Argument","expected at most 4 values"));
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
unittest
{
    import argparse.api.argument: PositionalArgument, NamedArgument;

    struct T
    {
        @NamedArgument bool c;
        @PositionalArgument string fileName;
    }

    enum Config cfg = { stylingMode: Config.StylingMode.off };

    {
        T t;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(t, ["-", "-c"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(t == T(true, "-"));
    }
    {
        T t;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(t, ["-c", "-"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(t == T(true, "-"));
    }
    {
        T t;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(t, ["-"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(t == T(false, "-"));
    }
    {
        T t;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(t, ["-f","-"], unrecognizedArgs));
        assert(unrecognizedArgs == ["-f"]);
        assert(t == T(false, "-"));
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

unittest
{
    struct T
    {
        string a;
        string baz;
    }

    enum Config cfg = { shortNamePrefix: "+", longNamePrefix: "==" };

    {
        T t;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(t, ["+a", "foo", "==baz", "BAZZ"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(t == T("foo", "BAZZ"));
    }
    {
        T t;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(t, ["+a", "foo", "++baz", "BAZZ"], unrecognizedArgs));
        assert(unrecognizedArgs == ["++baz", "BAZZ"]);
        assert(t == T("foo", ""));
    }
    {
        T t;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(t, ["=a", "foo", "==baz", "BAZZ"], unrecognizedArgs));
        assert(unrecognizedArgs == ["=a", "foo"]);
        assert(t == T("", "BAZZ"));
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

unittest
{
    import argparse.api.subcommand: SubCommand;

    struct c1 {
        string foo;
        string boo;
    }
    struct cmd {
        string foo;
        SubCommand!(c1) c;
    }

    enum Config cfg = { stylingMode: Config.StylingMode.off };

    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["--foo","FOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO"));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["--boo","BOO"], unrecognizedArgs));
        assert(unrecognizedArgs == ["--boo","BOO"]);
        assert(c == cmd.init);
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["--foo","FOO","--boo","BOO"], unrecognizedArgs));
        assert(unrecognizedArgs == ["--boo","BOO"]);
        assert(c == cmd("FOO"));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["--boo","BOO","--foo","FOO"], unrecognizedArgs));
        assert(unrecognizedArgs == ["--boo","BOO"]);
        assert(c == cmd("FOO"));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["c1","--boo","BOO","--foo","FOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("", typeof(c.c)(c1("FOO","BOO"))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["--foo","FOO","c1","--boo","BOO","--foo","FAA"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1("FAA","BOO"))));
    }
}

unittest
{
    import argparse.api.subcommand: Default, SubCommand;

    struct c1 {
        string foo;
        string boo;
    }
    struct cmd {
        string foo;
        SubCommand!(Default!c1) c;
    }

    enum Config cfg = { stylingMode: Config.StylingMode.off };

    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["--foo","FOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO"));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["--boo","BOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("", typeof(c.c)(c1("","BOO"))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["--foo","FOO","--boo","BOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1("","BOO"))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["--boo","BOO","--foo","FOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("", typeof(c.c)(c1("FOO","BOO"))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["c1","--boo","BOO","--foo","FOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("", typeof(c.c)(c1("FOO","BOO"))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["--foo","FOO","c1","--boo","BOO","--foo","FAA"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1("FAA","BOO"))));
    }
}


unittest
{
    import argparse.api.argument;
    import argparse.api.subcommand: SubCommand;

    struct c1 {
        @PositionalArgument
        string foo;
        @(PositionalArgument.Optional)
        string boo;
    }
    struct cmd {
        @PositionalArgument
        string foo;

        SubCommand!(c1) c;
    }

    enum Config cfg = { stylingMode: Config.StylingMode.off };

    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["FOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO"));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["FOO","FAA"], unrecognizedArgs));
        assert(unrecognizedArgs == ["FAA"]);
        assert(c == cmd("FOO"));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["--","FOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO"));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["FOO","--","FAA"], unrecognizedArgs));
        assert(unrecognizedArgs == ["FAA"]);
        assert(c == cmd("FOO"));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["FOO","FAA","BOO"], unrecognizedArgs));
        assert(unrecognizedArgs == ["FAA","BOO"]);
        assert(c == cmd("FOO"));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["c1","FOO"], unrecognizedArgs));
        assert(unrecognizedArgs == ["FOO"]);
        assert(c == cmd("c1"));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["--","c1","FOO"], unrecognizedArgs));
        assert(unrecognizedArgs == ["FOO"]);
        assert(c == cmd("c1"));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["FOO","c1","FAA"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1("FAA"))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["FOO","c1","FAA","BOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1("FAA","BOO"))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["FOO","c1","--","FAA","BOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1("FAA","BOO"))));
    }
}


unittest
{
    import argparse.api.argument;
    import argparse.api.subcommand: Default, SubCommand;

    struct c1 {
        @PositionalArgument
        string foo;
        @(PositionalArgument.Optional)
        string boo;
    }
    struct cmd {
        @PositionalArgument
        string foo;

        SubCommand!(Default!c1) c;
    }

    enum Config cfg = { stylingMode: Config.StylingMode.off };

    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["FOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO"));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["FOO","FAA"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1("FAA"))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["FOO","FAA","BOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1("FAA","BOO"))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["--","FOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO"));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["FOO","--","FAA"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1("FAA"))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["--","FOO","FAA","BOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1("FAA","BOO"))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["c1","FOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("c1", typeof(c.c)(c1("FOO"))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["FOO","c1","FAA"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1("FAA"))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["FOO","c1","FAA","BOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1("FAA","BOO"))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["FOO","c1","--","FAA","BOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1("FAA","BOO"))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["--","FOO","c1","FAA"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1("c1","FAA"))));
    }
}


unittest
{
    import argparse.api.argument: PositionalArgument, NamedArgument;
    import argparse.api.subcommand: Default, SubCommand;

    struct c2 {
        @PositionalArgument
        string foo;
        @PositionalArgument
        string boo;
        @NamedArgument
        string bar;
    }
    struct c1 {
        @PositionalArgument
        string foo;
        @PositionalArgument
        string boo;

        SubCommand!(Default!c2) c;
    }
    struct cmd {
        @PositionalArgument
        string foo;

        SubCommand!(Default!c1) c;
    }

    enum Config cfg = { stylingMode: Config.StylingMode.off };

    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["FOO","FAA","BOO","FEE","BEE"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1("FAA","BOO", typeof(c1.c)(c2("FEE","BEE"))))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["--bar","BAR","FOO","FAA","BOO","FEE","BEE"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1("FAA","BOO", typeof(c1.c)(c2("FEE","BEE","BAR"))))));
    }
}


unittest
{
    import argparse.api.argument: PositionalArgument, NamedArgument;
    import argparse.api.subcommand: Default, SubCommand;

    struct c2 {
        @PositionalArgument
        string foo;
        @PositionalArgument
        string boo;
        @NamedArgument
        string bar;
    }
    struct c1 {
        SubCommand!(Default!c2) c;
    }
    struct cmd {
        @PositionalArgument
        string foo;

        SubCommand!(Default!c1) c;
    }

    enum Config cfg = { stylingMode: Config.StylingMode.off };

    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["FOO","FAA","BOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1(typeof(c1.c)(c2("FAA","BOO"))))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["--bar","BAR","FOO","FAA","BOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1(typeof(c1.c)(c2("FAA","BOO","BAR"))))));
    }
    {
        cmd c;
        string[] unrecognizedArgs;
        assert(callParser!(cfg, false)(c, ["FOO","c2","FAA","BOO"], unrecognizedArgs));
        assert(unrecognizedArgs.length == 0);
        assert(c == cmd("FOO", typeof(c.c)(c1(typeof(c1.c)(c2("FAA","BOO"))))));
    }
}