module argparse.help;

import argparse: ArgumentInfo, Config, ArgumentGroup, Group, CommandInfo, Command, NamedArgument, PositionalArgument, TrailingArguments, AllowedValues;
import argparse.internal;

import std.sumtype: SumType, match;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/// Help printing functions
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package struct Item
{
    string name;
    LazyString description;
}

package struct Section
{
    string title;
    LazyString description;
    LazyString epilog;

    SumType!(Item[], Section[]) entries;

    @property bool empty() const
    {
        return title.length == 0 || entries.match!(_ => _.length) == 0;
    }

    private ulong maxItemNameLength() const
    {
        import std.algorithm: maxElement, map;

        return entries.match!(
                (const ref Section[] _) => _.map!(_ => _.maxItemNameLength()).maxElement(0),
                (const ref Item[] _) => _.map!(_ => _.name.length).maxElement(0));
    }
}

unittest
{
    Section s;
    assert(s.empty);
    s.title = "title";
    assert(s.empty);

    Section s1;
    s1.entries = [Item.init, Item.init];
    assert(s1.empty);
    s1.title = "title";
    assert(!s1.empty);

    Section s2;
    s2.entries = [Section.init];
    assert(s2.empty);
    s2.title = "title";
    assert(!s2.empty);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private void print(void delegate(string) sink, const ref Item item, string indent, string descriptionIndent, bool unused = false)
{
    auto description = item.description.get;
    if(description.length == 0)
    {
        sink(indent);
        sink(item.name);
        sink("\n");
    }
    else if(indent.length + item.name.length + 2 > descriptionIndent.length) // 2 = two spaces between name and description
    {
        // long name; start description on the next line
        sink(indent);
        sink(item.name);
        sink("\n");
        wrapMutiLine(sink, description, descriptionIndent, descriptionIndent);
    }
    else
    {
        import std.conv: text;

        wrapMutiLine(sink,
                     description,
                     text(indent, item.name, spaces(descriptionIndent.length - indent.length - item.name.length)),
                     descriptionIndent);
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private void print(void delegate(string) sink, const ref Section section, string indent, string descriptionIndent, bool topLevel = true)
{
    if(section.empty)
        return;

    import std.sumtype: match;

    sink(indent);
    sink(section.title);

    if(topLevel)
        sink("\n");
    else
    {
        sink(":\n");

        indent ~= "  ";
    }

    auto description = section.description.get;
    if(description.length > 0)
    {
        sink(indent);
        sink(description);
        sink("\n\n");
    }

    section.entries.match!((const ref entries)
    {
        foreach(const ref entry; entries)
            print(sink, entry, indent, descriptionIndent, false);
    });

    auto epilog = section.epilog.get;
    if(epilog.length > 0)
    {
        sink(indent);
        sink(epilog);
        sink("\n");
    }

    if(!topLevel)
        sink("\n");
}

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

private string getProgramName()
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

private void substituteProg(void delegate(string) sink, string text, string prog)
{
    import std.array: replaceInto;
    replaceInto(sink, text, "%(PROG)", prog);
}

unittest
{
    import std.array: appender;
    auto a = appender!string;
    substituteProg(_ => a.put(_), "this is some text where %(PROG) is substituted but PROG and prog are not", "-myprog-");
    assert(a[] == "this is some text where -myprog- is substituted but PROG and prog are not");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private string spaces(ulong num)
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

private void wrapMutiLine(void delegate(string) sink,
                          string s,
                          string firstindent = null,
                          string indent = null,
                          in size_t columns = 80,
                          in size_t tabsize = 8)
{
    import std.string: wrap, lineSplitter, join;
    import std.algorithm: map, each;

    if(s.length == 0)
        return;

    auto lines = s.lineSplitter;

    sink(lines.front.wrap(columns, firstindent, indent, tabsize));
    lines.popFront;

    lines.map!(s => s.wrap(columns, indent, indent, tabsize)).each!sink;
}

unittest
{
    string test(string s, size_t columns, string firstindent = null, string indent = null)
    {
        import std.array: appender;
        auto a = appender!string;
        wrapMutiLine(_ => a.put(_), s, firstindent, indent, columns);
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

private void printValue(void delegate(string) sink, in ArgumentInfo info)
{
    if(info.maxValuesCount.get == 0)
        return;

    if(info.minValuesCount.get == 0)
        sink("[");

    sink(info.placeholder);
    if(info.maxValuesCount.get > 1)
        sink(" ...");

    if(info.minValuesCount.get == 0)
        sink("]");
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
        printValue(_ => a.put(_), info);
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

private void printInvocation(void delegate(string) sink, in ArgumentInfo info, in string[] names, in Config config)
{
    if(info.positional)
        printValue(sink, info);
    else
    {
        import std.algorithm: each, map;

        names.each!((i, name)
        {
            if(i > 0)
                sink(", ");

            sink(getArgumentName(name, config));

            if(info.maxValuesCount.get > 0)
            {
                sink(" ");
                printValue(sink, info);
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
        printInvocation(_ => a.put(_), info.setDefaults!(int, "foo"), ["f","foo"], Config.init);
        return a[];
    }

    assert(test!false == "-f v, --foo v");
    assert(test!true == "v");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private void printUsage(void delegate(string) sink, in ArgumentInfo info, in Config config)
{
    if(!info.required)
        sink("[");

    printInvocation(sink, info, [info.names[0]], config);

    if(!info.required)
        sink("]");
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
        printUsage(_ => a.put(_), info.setDefaults!(int, "foo"), Config.init);
        return a[];
    }

    assert(test!(false, false) == "[--foo v]");
    assert(test!(false, true) == "[v]");
    assert(test!(true, false) == "--foo v");
    assert(test!(true, true) == "v");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private void printUsage(T)(void delegate(string) sink, in CommandArguments!T cmd, in Config config)
{
    import std.algorithm: map;
    import std.array: join;

    string progName = (cmd.parentNames ~ cmd.info.names[0]).map!(_ => _.length > 0 ? _ : getProgramName()).join(" ");

    sink("Usage: ");

    auto usage = cmd.info.usage.get;
    if(usage.length > 0)
        substituteProg(sink, usage, progName);
    else
    {
        import std.algorithm: filter, each, map;

        alias print = (r) => r
            .filter!((ref _) => !_.hideFromHelp)
            .each!((ref _)
            {
                sink(" ");
                printUsage(sink, _, config);
            });

        sink(progName);

        // named args
        print(cmd.arguments.arguments.filter!((ref _) => !_.positional));
        // positional args
        print(cmd.arguments.positionalArguments.map!(ref (_) => cmd.arguments.arguments[_]));
        // sub commands
        if(cmd.subCommands.length > 0)
            sink(" <command> [<args>]");
    }

    sink("\n");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private auto getSections(const(Arguments)* arguments, in Config config)
{
    import std.algorithm: filter, map;
    import std.array: appender, array;
    import std.range: chain;

    bool hideHelpArg = false;

    alias showArg = (ref _)
    {
        if(_.hideFromHelp)
            return false;

        if(isHelpArgument(_.names[0]))
        {
            if(hideHelpArg)
                return false;

            hideHelpArg = true;
        }

        return true;
    };

    alias getItem = (ref _)
    {
        auto invocation = appender!string;
        printInvocation(_ => invocation.put(_), _, _.names, config);

        return Item(invocation[], _.description);
    };

    Section[] sections;
    size_t[string] sectionMap;

    for(; arguments; arguments = arguments.parentArguments)
    {
        //user-defined groups first, then required args and then optional args
        foreach(ref group; chain(arguments.groups[2..$], [arguments.requiredGroup, arguments.optionalGroup]))
        {
            auto p = (group.name in sectionMap);
            ulong index;
            if(p !is null)
                index = *p;
            else
            {
                index = sectionMap[group.name] = sections.length;
                sections ~= Section(group.name, group.description);
            }

            sections[index].entries.match!(
                (ref Item[] items) {
                    items ~= group.arguments
                        .map!(_ => &arguments.arguments[_])
                        .filter!((const _) => showArg(*_))
                        .map!((const _) => getItem(*_))
                        .array;
                },
                (_){});
        }
    }

    return sections;
}

private auto getSection(in CommandInfo[] commands, in Config config)
{
    import std.algorithm: filter, map;
    import std.array: array, join;

    alias showArg = (ref _)
    {
        //if(_.hideFromHelp)
        //    return false;

        return _.names.length > 0 && _.names[0].length > 0;
    };

    alias getItem = (ref _)
    {
        return Item(_.names.join(","), LazyString(() {
            auto shortDescription = _.shortDescription.get;
            return shortDescription.length > 0 ? shortDescription : _.description.get;
        }));
    };

    auto section = Section("Available commands");

    // pre-compute the output
    section.entries = commands
        .filter!showArg
        .map!getItem
        .array;

    return section;
}

private auto getSection(T)(in CommandArguments!T cmd, in Config config)
{
    import std.array: appender;

    auto usage = appender!string;

    printUsage(_ => usage.put(_), cmd, config);

    Section[] sections;

    // sub commands
    if(cmd.subCommands.length > 0)
        sections ~= getSection(cmd.subCommands, config);

    sections ~= getSections(&cmd.arguments, config);

    auto section = Section(usage[], cmd.info.description, cmd.info.epilog);
    section.entries = sections;

    return section;
}

package void printHelp(T)(void delegate(string) sink, in CommandArguments!T cmd, in Config config)
{
    import std.algorithm: min;

    auto section = getSection(cmd, config);

    immutable helpPosition = min(section.maxItemNameLength() + 4, 24);
    immutable indent = spaces(helpPosition + 2);

    print(sink, section, "", indent);
}

unittest
{
    static auto epilog() { return "custom epilog"; }
    @(Command("MYPROG")
     .Description("custom description")
     .Epilog(epilog)
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

    auto test()
    {
        import std.array: appender;

        auto a = appender!string;
        printHelp(_ => a.put(_), CommandArguments!T(Config.init), Config.init);
        return a[];
    }
    static assert(test().length > 0);  // ensure that it works at compile time

    assert(test()  == "Usage: MYPROG [-s S] [-p VALUE] -f {apple,pear} [-i {1,4,16,8}] [-h] param0 {q,a}\n\n"~
        "custom description\n\n"~
        "Required arguments:\n"~
        "  -f {apple,pear}, --fruit {apple,pear}\n"~
        "                          This is a help text for fruit. Very very very very\n"~
        "                          very very very very very very very very very very very\n"~
        "                          very very very very long text\n"~
        "  param0                  This is a help text for param0. Very very very very\n"~
        "                          very very very very very very very very very very very\n"~
        "                          very very very very long text\n"~
        "  {q,a}\n\n"~
        "Optional arguments:\n"~
        "  -s S\n"~
        "  -p VALUE\n"~
        "  -i {1,4,16,8}\n"~
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

    import std.array: appender;

    auto a = appender!string;
    printHelp(_ => a.put(_), CommandArguments!T(Config.init), Config.init);

    assert(a[]  == "Usage: MYPROG [-a A] [-b B] [-c C] [-d D] [-h] p q\n\n"~
        "group1:\n"~
        "  group1 description\n\n"~
        "  -a A\n"~
        "  -b B\n"~
        "  p\n\n"~
        "group2:\n"~
        "  group2 description\n\n"~
        "  -c C\n"~
        "  -d D\n\n"~
        "Required arguments:\n"~
        "  q\n\n"~
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

    import std.array: appender;

    auto a = appender!string;
    printHelp(_ => a.put(_), CommandArguments!T(Config.init), Config.init);

    assert(a[]  == "Usage: MYPROG [-c C] [-d D] [-h] <command> [<args>]\n\n"~
        "Available commands:\n"~
        "  cmd1                    Perform cmd 1\n"~
        "  very-long-command-name-2\n"~
        "                          Perform cmd 2\n\n"~
        "Optional arguments:\n"~
        "  -c C\n"~
        "  -d D\n"~
        "  -h, --help              Show this help message and exit\n\n");
}
