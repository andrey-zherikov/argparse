module argparse.internal.tokenizer;

import argparse.config;
import argparse.param;
import argparse.result;
import argparse.internal.arguments: ArgumentInfo;
import argparse.internal.command: Command;
import argparse.internal.commandstack;

import std.range;
import std.sumtype: SumType;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private string[] consumeValuesFromCLI(ref string[] args,
                                      size_t minValuesCount, size_t maxValuesCount,
                                      bool delegate(string) isArgumentValue)
{
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

private string[] splitValues(string value, char valueSep, const(ArgumentInfo)* info)
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

package struct Unknown {
    string value;
}

package struct Argument {
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

package struct SubCommand {
    Command delegate() cmdInit;
}

private alias Token = SumType!(Unknown, Argument, SubCommand);

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private Token getNextToken(const ref Config config, ref string[] args,
    FindResult delegate(bool) findPositionalArg,
    FindResult delegate(string) findShortNamedArg,
    FindResult delegate(string) findLongNamedArg,
    Command delegate() delegate(string) findCommand)
{
    import std.algorithm : startsWith, min;
    import std.string : indexOf;

    assert(args.length > 0);

    const arg0 = args[0];

    if(arg0.length == 0)
    {
        args.popFront;
        return Token(Unknown(arg0));
    }

    auto isArgumentValue = (string str)
    {
        return str.length == 0 ||                           // empty string is a value
        str != config.endOfNamedArgs &&              // `--` is not a value
        !str.startsWith(config.shortNamePrefix) &&   // short name is not a value
        !str.startsWith(config.longNamePrefix) &&    // long name is not a value
        findCommand(str) is null;                    // command is not a value
    };

    auto createArgument = (string name, string[] values, FindResult res) => Token(Argument(RawParam(&config, name, values), res));

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
                    config.variadicNamedArgument ? res.arg.info.minValuesCount.get : min(1, res.arg.info.minValuesCount.get),
                    config.variadicNamedArgument ? res.arg.info.maxValuesCount.get : min(1, res.arg.info.maxValuesCount.get),
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
                    config.variadicNamedArgument ? res.arg.info.minValuesCount.get : min(1, res.arg.info.minValuesCount.get),
                    config.variadicNamedArgument ? res.arg.info.maxValuesCount.get : min(1, res.arg.info.maxValuesCount.get),
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
            auto res = findPositionalArg(false);
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
                return Token(SubCommand(cmdInit));
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
            auto res = findPositionalArg(true);
            if (res.arg)
            {
                auto values = consumeValuesFromCLI(args, res.arg.info.minValuesCount.get, res.arg.info.maxValuesCount.get, isArgumentValue);
                return createArgument(res.arg.info.placeholder, values, res);
            }
        }
    }

    args.popFront;
    return Token(Unknown(arg0));
}

private Token getNextPositionalArgument(const ref Config config, ref string[] args,
    FindResult delegate() findPositionalArg)
{
    assert(args.length > 0);

    auto createEntry(FindResult res)
    {
        auto values = consumeValuesFromCLI(args, res.arg.info.minValuesCount.get, res.arg.info.maxValuesCount.get, _ => true);
        return Token(Argument(RawParam(&config, res.arg.info.placeholder, values), res));
    }

    auto res = findPositionalArg();
    if(res.arg)
    return createEntry(res);

    const arg0 = args[0];
    args.popFront;
    return Token(Unknown(arg0));
}

unittest
{
    Config config = { bundling: false };
    auto args = [""];

    assert(getNextToken(config, args, null, null, null, null) == Token(Unknown("")));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package struct Tokenizer
{
    const Config config;
    string[] args;
    CommandStack* cmdStack;

    bool hitEndOfNamedArgs = false;

    void checkEndOfNamedArgs()
    {
        // Is it "--"?
        if(!hitEndOfNamedArgs && args.length > 0 && args[0] == config.endOfNamedArgs)
        {
            args = args[1..$];
            hitEndOfNamedArgs = true;
        }
    }

    bool empty() const { return args.length == 0; }

    auto getNext()
    {
        if(hitEndOfNamedArgs)
            return getNextPositionalArgument(config, args,
                () => cmdStack.getNextPositionalArgument(true),
            );
        else
        {
            checkEndOfNamedArgs();

            auto tok = getNextToken(config, args,
                lookInDefaultSubCommands => cmdStack.getNextPositionalArgument(lookInDefaultSubCommands),
                name => cmdStack.findShortArgument(name),
                name => cmdStack.findLongArgument(name),
                name => cmdStack.findSubCommand(name)
            );

            checkEndOfNamedArgs();

            return tok;
        }
    }

    int opApply(scope int delegate(Token tok) dg)
    {
        while(!empty)
        {
            int result = dg(getNext());
            if (result)
                return result;
        }
        return 0;
    }
}
