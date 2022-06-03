module argparse.help;

import argparse;
import argparse.internal;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/// Help printing functions
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package enum helpArgument = {
    ArgumentInfo arg;
    arg.names = ["h","help"];
    arg.description = "Show this help message and exit";
    arg.minValuesCount = 0;
    arg.maxValuesCount = 0;
    arg.allowBooleanNegation = false;
    arg.ignoreInDefaultCommand = true;
    return arg;
}();

private bool isHelpArgument(string name)
{
    static foreach(n; helpArgument.names)
        if(n == name)
            return true;

    return false;
}

unittest
{
    assert(isHelpArgument("h"));
    assert(isHelpArgument("help"));
    assert(!isHelpArgument("a"));
    assert(!isHelpArgument("help1"));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package string getProgramName()
{
    import core.runtime: Runtime;
    import std.path: baseName;
    return Runtime.args[0].baseName;
}

unittest
{
    assert(getProgramName().length > 0);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package void substituteProg(Output)(auto ref Output output, string text, string prog)
{
    import std.array: replaceInto;
    output.replaceInto(text, "%(PROG)", prog);
}

unittest
{
    import std.array: appender;
    auto a = appender!string;
    a.substituteProg("this is some text where %(PROG) is substituted but PROG and prog are not", "-myprog-");
    assert(a[] == "this is some text where -myprog- is substituted but PROG and prog are not");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package string spaces(ulong num)
{
    import std.range: repeat;
    import std.array: array;
    return ' '.repeat(num).array;
}

unittest
{
    assert(spaces(0) == "");
    assert(spaces(1) == " ");
    assert(spaces(5) == "     ");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package void wrapMutiLine(Output, S)(auto ref Output output,
S s,
in size_t columns = 80,
S firstindent = null,
S indent = null,
in size_t tabsize = 8)
{
    import std.string: wrap, lineSplitter, join;
    import std.algorithm: map, copy;

    auto lines = s.lineSplitter;
    if(lines.empty)
    {
        output.put(firstindent);
        output.put("\n");
        return;
    }

    output.put(lines.front.wrap(columns, firstindent, indent, tabsize));
    lines.popFront;

    lines.map!(s => s.wrap(columns, indent, indent, tabsize)).copy(output);
}

unittest
{
    string test(string s, size_t columns, string firstindent = null, string indent = null)
    {
        import std.array: appender;
        auto a = appender!string;
        a.wrapMutiLine(s, columns, firstindent, indent);
        return a[];
    }
    assert(test("a short string", 7) == "a short\nstring\n");
    assert(test("a\nshort string", 7) == "a\nshort\nstring\n");

    // wrap will not break inside of a word, but at the next space
    assert(test("a short string", 4) == "a\nshort\nstring\n");

    assert(test("a short string", 7, "\t") == "\ta\nshort\nstring\n");
    assert(test("a short string", 7, "\t", "    ") == "\ta\n    short\n    string\n");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private void printValue(Output)(auto ref Output output, in ArgumentInfo info)
{
    if(info.maxValuesCount.get == 0)
        return;

    if(info.minValuesCount.get == 0)
        output.put('[');

    output.put(info.placeholder);
    if(info.maxValuesCount.get > 1)
        output.put(" ...");

    if(info.minValuesCount.get == 0)
        output.put(']');
}

unittest
{
    auto test(int min, int max)
    {
        ArgumentInfo info;
        info.placeholder = "v";
        info.minValuesCount = min;
        info.maxValuesCount = max;

        import std.array: appender;
        auto a = appender!string;
        a.printValue(info);
        return a[];
    }

    assert(test(0,0) == "");
    assert(test(0,1) == "[v]");
    assert(test(0,5) == "[v ...]");
    assert(test(1,1) == "v");
    assert(test(1,5) == "v ...");
    assert(test(3,3) == "v ...");
    assert(test(3,5) == "v ...");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private void printInvocation(Output)(auto ref Output output, in ArgumentInfo info, in string[] names, in Config config)
{
    if(info.positional)
        output.printValue(info);
    else
    {
        import std.algorithm: each;

        names.each!((i, name)
        {
            if(i > 0)
                output.put(", ");

            output.put(getArgumentName(name, config));

            if(info.maxValuesCount.get > 0)
            {
                output.put(' ');
                output.printValue(info);
            }
        });
    }
}

unittest
{
    auto test(bool positional)()
    {
        enum info = {
            ArgumentInfo info;
            info.placeholder = "v";
            static if (positional)
                info.position = 0;
            return info;
        }();

        import std.array: appender;
        auto a = appender!string;
        a.printInvocation(info.setDefaults!(int, "foo"), ["f","foo"], Config.init);
        return a[];
    }

    assert(test!false == "-f v, --foo v");
    assert(test!true == "v");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private void printUsage(Output)(auto ref Output output, in ArgumentInfo info, in Config config)
{
    if(!info.required)
        output.put('[');

    output.printInvocation(info, [info.names[0]], config);

    if(!info.required)
        output.put(']');
}

unittest
{
    auto test(bool required, bool positional)()
    {
        enum info = {
            ArgumentInfo info;
            info.names ~= "foo";
            info.placeholder = "v";
            info.required = required;
            static if (positional)
                info.position = 0;
            return info;
        }();

        import std.array: appender;
        auto a = appender!string;
        a.printUsage(info.setDefaults!(int, "foo"), Config.init);
        return a[];
    }

    assert(test!(false, false) == "[--foo v]");
    assert(test!(false, true) == "[v]");
    assert(test!(true, false) == "--foo v");
    assert(test!(true, true) == "v");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private void printUsage(T, Output)(auto ref Output output, in CommandArguments!T cmd, in Config config)
{
    import std.algorithm: map;
    import std.array: join;

    string progName = (cmd.parentNames ~ cmd.info.names[0]).map!(_ => _.length > 0 ? _ : getProgramName()).join(" ");

    output.put("Usage: ");

    if(cmd.info.usage.length > 0)
        substituteProg(output, cmd.info.usage, progName);
    else
    {
        import std.algorithm: filter, each, map;

        alias print = (r) => r
            .filter!((ref _) => !_.hideFromHelp)
            .each!((ref _)
            {
                output.put(' ');
                argparse.help.printUsage(output, _, config);
            });

        output.put(progName);

        // named args
        print(cmd.arguments.arguments.filter!((ref _) => !_.positional));
        // positional args
        print(cmd.arguments.positionalArguments.map!(ref (_) => cmd.arguments.arguments[_]));
        // sub commands
        if(cmd.subCommands.length > 0)
            output.put(" <command> [<args>]");
    }

    output.put('\n');
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private void printUsage(T, Output)(auto ref Output output, in Config config)
{
    printUsage(output, CommandArguments!T(config), config);
}

unittest
{
    @(Command("MYPROG").Usage("custom usage of %(PROG)"))
    struct T
    {
        string s;
    }

    auto test(string usage)
    {
        import std.array: appender;

        auto a = appender!string;
        a.printUsage!T(Config.init);
        return a[];
    }

    enum expected = "Usage: custom usage of MYPROG\n";
    static assert(test("custom usage of %(PROG)") == expected);
    assert(test("custom usage of %(PROG)") == expected);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private void printHelp(Output, ARGS)(auto ref Output output, in Group group, ARGS args, int helpPosition)
{
    import std.string: leftJustify;

    if(group.arguments.length == 0 || group.name.length == 0)
        return;

    alias printDescription = {
        output.put(group.name);
        output.put(":\n");

        if (group.description.length > 0)
        {
            output.put("  ");
            output.put(group.description);
            output.put("\n\n");
        }
    };
    bool descriptionIsPrinted = false;

    immutable ident = spaces(helpPosition + 2);

    foreach(idx; group.arguments)
    {
        auto arg = &args[idx];

        if(arg.invocation.length == 0)
            continue;

        if(!descriptionIsPrinted)
        {
            printDescription();
            descriptionIsPrinted = true;
        }

        if(arg.invocation.length <= helpPosition - 4) // 2=indent, 2=two spaces between invocation and help text
        {
            import std.array: appender;

            auto invocation = appender!string;
            invocation ~= "  ";
            invocation ~= arg.invocation.leftJustify(helpPosition);
            output.wrapMutiLine(arg.help, 80-2, invocation[], ident);
        }
        else
        {
            // long action name; start on the next line
            output.put("  ");
            output.put(arg.invocation);
            output.put("\n");
            output.wrapMutiLine(arg.help, 80-2, ident, ident);
        }
    }

    output.put('\n');
}


private void printHelp(Output)(auto ref Output output, in Arguments arguments, in Config config, bool helpArgIsPrinted = false)
{
    import std.algorithm: map, maxElement, min;
    import std.array: appender, array;

    // pre-compute the output
    auto args =
        arguments.arguments
        .map!((ref _)
        {
            struct Result
            {
                string invocation, help;
            }

            if(_.hideFromHelp)
                return Result.init;

            if(isHelpArgument(_.names[0]))
            {
                if(helpArgIsPrinted)
                    return Result.init;

                helpArgIsPrinted = true;
            }

            auto invocation = appender!string;
            invocation.printInvocation(_, _.names, config);

            return Result(invocation[], _.description);
        }).array;

    immutable maxInvocationWidth = args.map!(_ => _.invocation.length).maxElement;
    immutable helpPosition = min(maxInvocationWidth + 4, 24);

    //user-defined groups
    foreach(ref group; arguments.groups[2..$])
        output.printHelp(group, args, helpPosition);

    //required args
    output.printHelp(arguments.requiredGroup, args, helpPosition);

    //optionals args
    output.printHelp(arguments.optionalGroup, args, helpPosition);

    if(arguments.parentArguments)
        output.printHelp(*arguments.parentArguments, config, helpArgIsPrinted);
}

private void printHelp(Output)(auto ref Output output, in CommandInfo[] commands, in Config config)
{
    import std.algorithm: map, maxElement, min;
    import std.array: appender, array, join;

    if(commands.length == 0)
        return;

    output.put("Available commands:\n");

    // pre-compute the output
    auto cmds = commands
        .map!((ref _)
        {
            struct Result
            {
                string invocation, help;
            }

            //if(_.hideFromHelp)
            //    return Result.init;

            return Result(_.names.join(","), _.shortDescription.length > 0 ? _.shortDescription : _.description);
        }).array;

    immutable maxInvocationWidth = cmds.map!(_ => _.invocation.length).maxElement;
    immutable helpPosition = min(maxInvocationWidth + 4, 24);


    immutable ident = spaces(helpPosition + 2);

    foreach(const ref cmd; cmds)
    {
        if(cmd.invocation.length == 0)
            continue;

        if(cmd.invocation.length <= helpPosition - 4) // 2=indent, 2=two spaces between invocation and help text
        {
            import std.array: appender;
            import std.string: leftJustify;

            auto invocation = appender!string;
            invocation ~= "  ";
            invocation ~= cmd.invocation.leftJustify(helpPosition);
            output.wrapMutiLine(cmd.help, 80-2, invocation[], ident);
        }
        else
        {
            // long action name; start on the next line
            output.put("  ");
            output.put(cmd.invocation);
            output.put("\n");
            output.wrapMutiLine(cmd.help, 80-2, ident, ident);
        }
    }

    output.put('\n');
}


private void printHelp(T, Output)(auto ref Output output, in CommandArguments!T cmd, in Config config)
{
    printUsage(output, cmd, config);
    output.put('\n');

    if(cmd.info.description.length > 0)
    {
        output.put(cmd.info.description);
        output.put("\n\n");
    }

    // sub commands
    output.printHelp(cmd.subCommands, config);

    output.printHelp(cmd.arguments, config);

    if(cmd.info.epilog.length > 0)
    {
        output.put(cmd.info.epilog);
        output.put('\n');
    }
}

void printHelp(T, Output)(auto ref Output output, in Config config)
{
    printHelp(output, CommandArguments!T(config), config);
}

unittest
{
    @(Command("MYPROG")
     .Description("custom description")
     .Epilog("custom epilog")
    )
    struct T
    {
        @NamedArgument  string s;
        @(NamedArgument.Placeholder("VALUE"))  string p;

        @(NamedArgument.HideFromHelp())  string hidden;

        enum Fruit { apple, pear };
        @(NamedArgument(["f","fruit"]).Required().Description("This is a help text for fruit. Very very very very very very very very very very very very very very very very very very very long text")) Fruit f;

        @(NamedArgument.AllowedValues!([1,4,16,8])) int i;

        @(PositionalArgument(0).Description("This is a help text for param0. Very very very very very very very very very very very very very very very very very very very long text")) string param0;
        @(PositionalArgument(1).AllowedValues!(["q","a"])) string param1;

        @TrailingArguments string[] args;
    }

    auto test(alias func)()
    {
        import std.array: appender;

        auto a = appender!string;
        func!T(a, Config.init);
        return a[];
    }
    static assert(test!printUsage.length > 0);  // ensure that it works at compile time
    static assert(test!printHelp .length > 0);  // ensure that it works at compile time

    assert(test!printUsage == "Usage: MYPROG [-s S] [-p VALUE] -f {apple,pear} [-i {1,4,16,8}] [-h] param0 {q,a}\n");
    assert(test!printHelp  == "Usage: MYPROG [-s S] [-p VALUE] -f {apple,pear} [-i {1,4,16,8}] [-h] param0 {q,a}\n\n"~
        "custom description\n\n"~
        "Required arguments:\n"~
        "  -f {apple,pear}, --fruit {apple,pear}\n"~
        "                          This is a help text for fruit. Very very very very\n"~
        "                          very very very very very very very very very very\n"~
        "                          very very very very very long text\n"~
        "  param0                  This is a help text for param0. Very very very very\n"~
        "                          very very very very very very very very very very\n"~
        "                          very very very very very long text\n"~
        "  {q,a}                   \n\n"~
        "Optional arguments:\n"~
        "  -s S                    \n"~
        "  -p VALUE                \n"~
        "  -i {1,4,16,8}           \n"~
        "  -h, --help              Show this help message and exit\n\n"~
        "custom epilog\n");
}

unittest
{
    @Command("MYPROG")
    struct T
    {
        @(ArgumentGroup("group1").Description("group1 description"))
        {
            @NamedArgument
            {
                string a;
                string b;
            }
            @PositionalArgument(0) string p;
        }

        @(ArgumentGroup("group2").Description("group2 description"))
        @NamedArgument
        {
            string c;
            string d;
        }
        @PositionalArgument(1) string q;
    }

    auto test(alias func)()
    {
        import std.array: appender;

        auto a = appender!string;
        func!T(a, Config.init);
        return a[];
    }

    assert(test!printHelp  == "Usage: MYPROG [-a A] [-b B] [-c C] [-d D] [-h] p q\n\n"~
        "group1:\n"~
        "  group1 description\n\n"~
        "  -a A          \n"~
        "  -b B          \n"~
        "  p             \n\n"~
        "group2:\n"~
        "  group2 description\n\n"~
        "  -c C          \n"~
        "  -d D          \n\n"~
        "Required arguments:\n"~
        "  q             \n\n"~
        "Optional arguments:\n"~
        "  -h, --help    Show this help message and exit\n\n");
}

unittest
{
    import std.sumtype: SumType;

    @Command("MYPROG")
    struct T
    {
        @(Command("cmd1").ShortDescription("Perform cmd 1"))
        struct CMD1
        {
            string a;
        }
        @(Command("very-long-command-name-2").ShortDescription("Perform cmd 2"))
        struct CMD2
        {
            string b;
        }

        string c;
        string d;

        SumType!(CMD1, CMD2) cmd;
    }

    auto test(alias func)()
    {
        import std.array: appender;

        auto a = appender!string;
        func!T(a, Config.init);
        return a[];
    }

    assert(test!printHelp  == "Usage: MYPROG [-c C] [-d D] [-h] <command> [<args>]\n\n"~
        "Available commands:\n"~
        "  cmd1                    Perform cmd 1\n"~
        "  very-long-command-name-2\n"~
        "                          Perform cmd 2\n\n"~
        "Optional arguments:\n"~
        "  -c C          \n"~
        "  -d D          \n"~
        "  -h, --help    Show this help message and exit\n\n");
}
