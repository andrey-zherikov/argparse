module argparse.internal.help;

import argparse.ansi;
import argparse.config;
import argparse.result;
import argparse.api.ansi: ansiStylingArgument;
import argparse.internal.lazystring;
import argparse.internal.arguments: ArgumentInfo, Arguments;
import argparse.internal.commandinfo: CommandInfo;
import argparse.internal.argumentuda: ArgumentUDA;
import argparse.internal.style;

import std.sumtype: SumType, match;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/// Help elements
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

    private ulong maxItemNameLength(ulong limit) const
    {
        import std.algorithm: maxElement, map, filter;

        return entries.match!(
                (const ref Section[] _) => _.map!(_ => _.maxItemNameLength(limit)).maxElement(0),
                (const ref Item[] _) => _.map!(_ => getUnstyledTextLength(_.name)).filter!(_ => _ <= limit).maxElement(0));
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
/// Help printing functions
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private void print(void delegate(string) sink, const ref Item item, string indent, string descriptionIndent, bool unused = false)
{
    auto nameLength = getUnstyledTextLength(item.name);

    sink(indent);
    sink(item.name);

    auto description = item.description.get;
    if(description.getUnstyledTextLength == 0)
    {
        sink("\n");
    }
    else if(indent.length + nameLength + 2 > descriptionIndent.length) // 2 = two spaces between name and description
    {
        // long name; start description on the next line
        sink("\n");
        wrap(sink, description, descriptionIndent, descriptionIndent);
    }
    else
    {
        wrap(sink, description, descriptionIndent[indent.length + nameLength..$], descriptionIndent, indent.length + nameLength);
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
    if(description.getUnstyledTextLength > 0)
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
    if(epilog.getUnstyledTextLength > 0)
    {
        sink(indent);
        sink(epilog);
        sink("\n");
    }

    if(!topLevel)
        sink("\n");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
package struct HelpArgumentUDA
{
    ArgumentInfo info = {
        ArgumentInfo info;
        info.shortNames = ["h"];
        info.longNames = ["help"];
        info.description = "Show this help message and exit";
        info.required = false;
        info.minValuesCount = 0;
        info.maxValuesCount = 0;
        info.allowBooleanNegation = false;
        info.ignoreInDefaultCommand = true;
        return info;
    }();

    auto parse(Config config, COMMAND_STACK, RECEIVER)(const COMMAND_STACK cmdStack, ref RECEIVER receiver, string argName, string[] rawValues)
    {
        import std.stdio: stdout;
        import std.algorithm: map;
        import std.array: join, array;

        string progName = cmdStack.map!((ref _) => _.displayName.length > 0 ? _.displayName : getProgramName()).join(" ");

        auto args = cmdStack.map!((ref _) => &_.arguments).array;

        auto output = stdout.lockingTextWriter();
        printHelp!config(_ => output.put(_), cmdStack[$-1], args, progName);

        return Result(0);
    }
}

unittest
{
    assert(HelpArgumentUDA.init.info.shortNames == ["h"]);
    assert(HelpArgumentUDA.init.info.longNames == ["help"]);
    assert(!HelpArgumentUDA.init.info.required);
    assert(HelpArgumentUDA.init.info.minValuesCount == 0);
    assert(HelpArgumentUDA.init.info.maxValuesCount == 0);
    assert(!HelpArgumentUDA.init.info.allowBooleanNegation);
    assert(HelpArgumentUDA.init.info.ignoreInDefaultCommand);
}

private bool isHelpArgument(string name)
{
    import std.range: chain;

    static foreach(n; chain(HelpArgumentUDA.init.info.shortNames, HelpArgumentUDA.init.info.longNames))
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

private void wrap(void delegate(string) sink,
                  string s,
                  string firstIndent,
                  string indent,
                  size_t firstColumns = 0,
                  size_t columns = 80)
{
    import std.string: lineSplitter;
    import std.range: enumerate;
    import std.algorithm: map;
    import std.typecons: tuple;
    import std.regex: ctRegex, splitter;

    if(s.length == 0)
        return;

    enum whitespaces = ctRegex!(`\s+`);

    foreach(lineIdx, line; s.lineSplitter.enumerate)
    {
        size_t col = 0;

        if(lineIdx == 0)
        {
            sink(firstIndent);
            col = firstColumns + firstIndent.length;
        }
        else
        {
            sink(indent);
            col = indent.length;
        }

        foreach(wordIdx, word; line.splitter(whitespaces).map!(_ => _, getUnstyledTextLength).enumerate)
        {
            if(wordIdx > 0)
            {
                if (col + 1 + word[1] > columns)
                {
                    sink("\n");
                    sink(indent);
                    col = indent.length;
                }
                else
                {
                    sink(" ");
                    col++;
                }
            }

            sink(word[0]);
            col += word[1];
        }

        sink("\n");
    }
}

unittest
{
    string test(string s, size_t columns, string firstIndent = null, string indent = null, size_t firstColumns = 0)
    {
        import std.array: appender;
        auto a = appender!string;
        wrap(_ => a.put(_), s, firstIndent, indent, firstColumns, columns);
        return a[];
    }
    assert(test("a short string", 7) == "a short\nstring\n");
    assert(test("a short string", 7, "-","+", 4) == "-a\n+short\n+string\n");
    assert(test("a\nshort string", 7) == "a\nshort\nstring\n");

    // wrap will not break inside of a word, but at the next space
    assert(test("a short string", 4) == "a\nshort\nstring\n");

    assert(test("a short string", 7, "\t") == "\ta\nshort\nstring\n");
    assert(test("a short string", 7, "\t", "    ") == "\ta\n    short\n    string\n");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private string printValue(in ArgumentInfo info)
{
    if(info.maxValuesCount.get == 0)
        return "";

    import std.array: appender;
    auto a = appender!string;

    if(info.minValuesCount.get == 0)
        a.put("[");

    a.put(info.placeholder);
    if(info.maxValuesCount.get > 1)
        a.put(" ...");

    if(info.minValuesCount.get == 0)
        a.put("]");

    return a[];
}

unittest
{
    auto test(int min, int max)
    {
        ArgumentInfo info;
        info.placeholder = "v";
        info.minValuesCount = min;
        info.maxValuesCount = max;

        return printValue(info);
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

private void printInvocation(NAMES)(void delegate(string) sink, const ref Style style, in ArgumentInfo info, NAMES names)
{
    if(info.positional)
        sink(style.positionalArgumentValue(printValue(info)));
    else
    {
        import std.algorithm: each;

        names.each!((i, name)
        {
            if(i > 0)
                sink(", ");

            sink(style.argumentName(name));

            if(info.maxValuesCount.get > 0)
            {
                sink(" ");
                sink(style.namedArgumentValue(printValue(info)));
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
            info.minValuesCount = 1;
            info.maxValuesCount = 1;
            static if (positional)
                info.position = 0;
            return info;
        }();

        import std.array: appender;
        auto a = appender!string;
        Style style;
        printInvocation(_ => a.put(_), style, info, ["-f","--foo"]);
        return a[];
    }

    assert(test!false == "-f v, --foo v");
    assert(test!true == "v");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private void printUsage(void delegate(string) sink, const ref Style style, in ArgumentInfo info)
{
    if(!info.required)
        sink("[");

    printInvocation(sink, style, info, [ info.displayName ]);

    if(!info.required)
        sink("]");
}

unittest
{
    auto test(bool required, bool positional)()
    {
        enum info = {
            ArgumentInfo info;
            info.longNames ~= "foo";
            info.displayNames ~= "--foo";
            info.placeholder = "v";
            info.required = required;
            info.minValuesCount = 1;
            info.maxValuesCount = 1;
            static if (positional)
                info.position = 0;
            return info;
        }();

        import std.array: appender;
        auto a = appender!string;
        Style style;
        printUsage(_ => a.put(_), style, info);
        return a[];
    }

    assert(test!(false, false) == "[--foo v]");
    assert(test!(false, true) == "[v]");
    assert(test!(true, false) == "--foo v");
    assert(test!(true, true) == "v");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private void createUsage(void delegate(string) sink, const ref Style style, string progName, const(Arguments)* arguments, bool hasSubCommands)
{
    import std.algorithm: filter, each;

    alias print = (r) => r
    .filter!((ref _) => !_.hideFromHelp)
    .each!((ref _)
    {
        sink(" ");
        printUsage(sink, style, _);
    });

    sink(progName);

    // named args
    print(arguments.namedArguments);
    // positional args
    print(arguments.positionalArguments);
    // sub commands
    if(hasSubCommands)
        sink(style.subcommandName(" <command> [<args>]"));
}

private string getUsage(Command)(const ref Style style, const ref Command cmd, string progName)
{
    import std.array: appender;

    auto usage = appender!string;

    usage.put("Usage: ");

    auto usageText = cmd.info.usage.get;
    if(usageText.length > 0)
        substituteProg(_ => usage.put(_), usageText, progName);
    else
        createUsage(_ => usage.put(_), style, progName, &cmd.arguments, cmd.subCommands.info.length > 0);

    usage.put("\n");

    return usage[];
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private auto getSections(ARGUMENTS)(const ref Style style, ARGUMENTS arguments)
{
    import std.algorithm: filter, map;
    import std.array: appender, array;
    import std.range: chain;

    bool hideHelpArg = false;

    alias showArg = (ref _)
    {
        if(_.hideFromHelp)
            return false;

        if(_.shortNames.length > 0 && isHelpArgument(_.shortNames[0]) ||
            _.longNames.length > 0 && isHelpArgument(_.longNames[0]))
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
        printInvocation(_ => invocation.put(_), style, _, _.displayNames);

        return Item(invocation[], _.description);
    };

    Section[] sections;
    size_t[string] sectionMap;

    foreach_reverse(ref args; arguments)
    {
        //user-defined groups first, then required args and then optional args
        foreach(ref group; chain(args.userGroups, [args.requiredGroup, args.optionalGroup]))
        {
            auto p = (group.name in sectionMap);
            ulong index;
            if(p !is null)
                index = *p;
            else
            {
                index = sectionMap[group.name] = sections.length;
                sections ~= Section(style.argumentGroupTitle(group.name), group.description);
            }

            sections[index].entries.match!(
                (ref Item[] items) {
                    items ~= group.argIndex
                        .map!(_ => &args.info[_])
                        .filter!((const _) => showArg(*_))
                        .map!((const _) => getItem(*_))
                        .array;
                },
                (_){});
        }
    }

    return sections;
}

private auto getSection(const ref Style style, in CommandInfo[] commands)
{
    import std.algorithm: filter, map;
    import std.array: array, join;

    alias showArg = (ref _)
    {
        //if(_.hideFromHelp)
        //    return false;

        return _.displayNames.length > 0 && _.displayNames[0].length > 0;
    };

    alias getItem = (ref _)
    {
        return Item(_.displayNames.map!(_ => style.subcommandName(_)).join(","), LazyString(() {
            auto shortDescription = _.shortDescription.get;
            return shortDescription.length > 0 ? shortDescription : _.description.get;
        }));
    };

    auto section = Section(style.argumentGroupTitle("Available commands"));

    // pre-compute the output
    section.entries = commands
        .filter!showArg
        .map!getItem
        .array;

    return section;
}

private auto getSection(Command)(const ref Style style, const ref Command cmd, Section[] argSections, string progName)
{
    Section[] sections;

    // sub commands
    if(cmd.subCommands.info.length > 0)
        sections ~= getSection(style, cmd.subCommands.info);

    sections ~= argSections;

    auto section = Section(getUsage(style, cmd, progName), cmd.info.description, cmd.info.epilog);
    section.entries = sections;

    return section;
}

package(argparse) void printHelp(Config config, ARGUMENTS, Command)(void delegate(string) sink, const ref Command cmd, ARGUMENTS arguments, string progName)
{
    import std.algorithm: each;

    auto style = ansiStylingArgument ? config.styling : Style.None;

    auto argSections = getSections(style, arguments);
    auto section = getSection(style, cmd, argSections, style.programName(progName));

    immutable helpPosition = section.maxItemNameLength(20) + 4;
    immutable indent = spaces(helpPosition + 2);

    print(ansiStylingArgument ? sink : (string _) { _.getUnstyledText.each!sink; }, section, "", indent);
}