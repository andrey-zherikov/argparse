module argparse.defaulthelpprinter;

import argparse.config;
import argparse.helpinfo;
import argparse.helpprinter;
import argparse.style;

import std.algorithm;
import std.conv: text;
import std.range;
import std.string;
import std.typecons: Nullable, nullable;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private string wrapOptional(bool optional, string str)
{
    return optional ? i"[$(str)]".text : str;
}

unittest
{
    assert(wrapOptional(false, "foo") == "foo");
    assert(wrapOptional(true, "foo") == "[foo]");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private string defaultMark(bool isDefault)
{
    return isDefault ? " (default)" : "";
}

unittest
{
    assert(defaultMark(false) == "");
    assert(defaultMark(true) == " (default)");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

public struct HelpScreen
{
    struct Parameter
    {
        string name;
        string description;
    }

    struct Group
    {
        string title;
        string description;

        Parameter[] parameters;
    }

    string usage;
    string description;
    string epilog;

    Group[] groups;
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Creates the object that renders help text. Every place that formats help goes through this function so
// that `Config.helpPrinterFactory` is honored consistently.
package HelpPrinter createHelpPrinter(const Config config, Style style, void delegate(string) sink)
{
    return config.helpPrinterFactory !is null ?
           config.helpPrinterFactory(config, style, sink) :
           new DefaultHelpPrinter(config, style, sink);
}

unittest
{
    string output;

    // No factory in config => the default implementation
    auto hp = createHelpPrinter(Config.init, Style.None, (_) { output ~= _; });

    assert(hp !is null);
    assert(cast(DefaultHelpPrinter) hp !is null);
    hp.printUsage([CommandHelpInfo(name: "prog")]);
    assert(output == "Usage: prog\n");   // the sink passed to createHelpPrinter is the one used
}

unittest
{
    // Config.helpPrinterFactory is used when it is provided, and it is given the sink to print to
    static class MyHelpPrinter : DefaultHelpPrinter
    {
        this(const Config config, Style style, void delegate(string) sink) { super(config, style, sink); }
    }

    static string captured;

    enum Config config = { helpPrinterFactory: (c, s, sink) => new MyHelpPrinter(c, s, sink) };

    auto hp = createHelpPrinter(config, Style.None, (_) { captured ~= _; });

    assert(cast(MyHelpPrinter) hp !is null);

    hp.printHelp([CommandHelpInfo(name: "prog")]);
    assert(captured == "Usage: prog\n\n");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

public class DefaultHelpPrinter : HelpPrinter
{
    const Config config;
    Style style;
    void delegate(string) sink;

    this(const Config config, Style style, void delegate(string) sink)
    {
        this.config = config;
        this.style = style;
        this.sink = sink;
    }


    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Function similar to std.string.wrap but with few adjustments:
    //   - Styling, if any, is removed during calculation of word length
    //   - It preserves line breaks '\n'
    //   - Output is returned in sink in pieces rather than in allocated string

    static void wrapText(void delegate(string) sink,
        string text,
        string firstIndent,
        string indent,
        size_t maxLineLength = 80)
    {
        if(text.length == 0)
            return;

        foreach(lineIdx, line; text.lineSplitter.enumerate)
        {
            size_t col = 0;

            if(lineIdx == 0)
            {
                sink(firstIndent);
                col = firstIndent.length;
            }
            else
            {
                sink(indent);
                col = indent.length;
            }

            foreach(wordIdx, word; line.splitter.map!(_ => _, getUnstyledTextLength).enumerate)
            {
                if(wordIdx > 0)
                {
                    if(col + 1 + word[1] > maxLineLength)
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


    ///////////////////////////////////////////////////////////////////////////
    // Formatting functions
    ///////////////////////////////////////////////////////////////////////////

    string formatArgumentValue(in ArgumentHelpInfo helpInfo)
    {
        if(helpInfo.placeholder.length == 0)
            return "";

        string placeholder = helpInfo.positional ? style.positionalArgumentValue(helpInfo.placeholder) : style.namedArgumentValue(helpInfo.placeholder);
        string dots = helpInfo.multipleOccurrence ? " ..." : "";

        return wrapOptional(helpInfo.optionalValue, placeholder ~ dots);
    }

    string formatArgumentUsage(in ArgumentHelpInfo helpInfo, bool usageString)
    {
        auto value = helpInfo.booleanFlag ? "" : formatArgumentValue(helpInfo);

        if(helpInfo.positional)
            return wrapOptional(helpInfo.optionalArgument, value);

        if(value.length > 0)
            value = " " ~ value; // prepend with space

        auto noPrefix = helpInfo.booleanFlag ? "[no-]" : "";

        auto nameValues = chain(
            helpInfo.shortNames.map!(_ => style.argumentName(config.shortNamePrefix ~ _) ~ value),
            helpInfo.longNames .map!(_ => style.argumentName(config.longNamePrefix ~ noPrefix ~ _) ~ value)
        );

        if(usageString)
        {
            // usage string contains only one agrument name (even if it has multiple names) and
            // includes square brackets '[]' if argument is optional
            return wrapOptional(helpInfo.optionalArgument, nameValues.front);
        }
        else
        {
            // argument description doesn't contain square brackets '[]' even when argument is optional
            // but shows all argument names
            return nameValues.join(", ");
        }
    }

    string formatArgumentDescription(in ArgumentHelpInfo helpInfo)
    {
        if(helpInfo.defaultValue.isNull)
            return helpInfo.description.idup;   // copy is needed to not return a slice of `scope` parameter

        auto value = helpInfo.positional ?
                     style.positionalArgumentValue(helpInfo.defaultValue.get) :
                     style.namedArgumentValue(helpInfo.defaultValue.get);

        auto mark = "(default: " ~ value ~ ")";

        return helpInfo.description.length > 0 ? helpInfo.description ~ " " ~ mark : mark;
    }

    // Returns the usage line (`Usage: ...`) for the provided stack of (sub)commands.
    // Both `printUsage` and the help screen use it, so overriding it changes the usage line everywhere.
    string formatUsage(const CommandHelpInfo[] commands)
    {
        auto helpInfo = &commands[$-1];

        if(helpInfo.usage.length > 0)
            return "Usage: " ~ replace(helpInfo.usage, "%(PROG)", commands.map!((ref _) => _.name).join(" "));

        return "Usage: " ~ chain(
                commands.map!((ref _) => _.name),
                helpInfo.namedArguments.map!((ref _) => formatArgumentUsage(_, true)),       // named arguments
                helpInfo.positionalArguments.map!((ref _) => formatArgumentUsage(_, true)),  // positional arguments
                helpInfo.subCommands.length > 0 ? ["<command> [<args>]"] : []          // subcommands if any
            ).join(" ");
    }

    // Prints the usage line (`Usage: ...`) for the provided stack of (sub)commands, terminated with `\n`.
    void printUsage(const CommandHelpInfo[] commands)
    {
        sink(formatUsage(commands));
        sink("\n");
    }

    ///////////////////////////////////////////////////////////////////////////
    // Functions to create help screen
    ///////////////////////////////////////////////////////////////////////////

    HelpScreen.Group createSubCommandGroup(const ref CommandHelpInfo cmd)
    {
        return HelpScreen.Group(
            title: style.argumentGroupTitle("Available commands"),
            parameters: cmd.subCommands
                .map!((ref _) =>
                    HelpScreen.Parameter(_.names.map!(_ => style.subcommandName(_)).join(",") ~ defaultMark(_.isDefault),
                                         _.description))
                .array
        );
    }

    HelpScreen.Group[] createArgumentsGroups(const ref CommandHelpInfo[] commands)
    {
        bool[string] processedArgs;

        alias showArg = (arg)
        {
            auto name = arg.shortNames.length > 0
                ? arg.shortNames[0]
                : arg.longNames[0];

            return !arg.hidden && !(name in processedArgs) ? (processedArgs[name] = true) : false;
        };


        HelpScreen.Group[] groups;
        size_t[string] groupMap;

        foreach_reverse(ref cmd; commands)
        {
            //user-defined groups first, then required args and then optional args
            foreach(ref group; chain(cmd.userGroups, [cmd.requiredGroup, cmd.optionalGroup]))
            {
                if(group.argIndex.length == 0)
                    continue;

                auto p = (group.name in groupMap);
                size_t index;
                if(p !is null)
                    index = *p;
                else
                {
                    index = groupMap[group.name] = groups.length;
                    groups ~= HelpScreen.Group(style.argumentGroupTitle(group.name), group.description);
                }

                groups[index].parameters ~= group.argIndex
                    .map!(_ => cmd.arguments[_])
                    .filter!(showArg)
                    .map!(_ => HelpScreen.Parameter(formatArgumentUsage(_, false), formatArgumentDescription(_)))
                    .array;
            }
        }

        return groups;
    }

    // Prints the provided arguments rendered as they appear on help screen: name column and wrapped
    // description. Every line, including the last one, is terminated with `\n`.
    void printArgumentList(const ArgumentHelpInfo[] args)
    {
        sink(formatArgumentList(args));
    }

    // Returns the text that `printArgumentList` prints.
    string formatArgumentList(const ArgumentHelpInfo[] args)
    {
        import std.array: appender;

        auto parameters = args
            .map!((ref _) => HelpScreen.Parameter(formatArgumentUsage(_, false), formatArgumentDescription(_)))
            .array;

        immutable offset = descriptionOffset(parameters);

        auto res = appender!string;

        foreach(const ref param; parameters)
            printParameter(_ => res.put(_), param, offset);

        return res[];
    }

    HelpScreen createHelpScreen(const CommandHelpInfo[] commands)
    {
        auto currentCmd = &commands[$-1];

        auto helpScreen = HelpScreen(formatUsage(commands),
                                     currentCmd.description,
                                     currentCmd.epilog);

        // sub commands go first
        if(currentCmd.subCommands.length > 0)
            helpScreen.groups ~= createSubCommandGroup(*currentCmd);

        // then arguments
        helpScreen.groups ~= createArgumentsGroups(commands);

        return helpScreen;
    }

    ///////////////////////////////////////////////////////////////////////////
    // Printing functions
    ///////////////////////////////////////////////////////////////////////////

    // These functions print to `output` rather than to `sink` so that a part of help screen can be rendered
    // somewhere else - for example, `formatArgumentList` renders parameters into a string.

    void printParameter(void delegate(string) output, const ref HelpScreen.Parameter param, size_t descriptionOffset)
    {
        string name = "  " ~ param.name;
        auto nameLength = name.getUnstyledTextLength();

        if(param.description.getUnstyledTextLength == 0)
        {
            output(name);
            output("\n");
        }
        else if(nameLength + 2 > descriptionOffset) // 2 = two spaces between name and description
        {
            // long name; start description on the next line
            output(name);
            output("\n");

            immutable descriptionIndent = ' '.repeat(descriptionOffset).array;
            wrapText(output, param.description, descriptionIndent, descriptionIndent);
        }
        else
        {
            // name is short enough to fit before the description on the first line
            // to render this correctly, we put name into first-line indent parameter

            immutable descriptionIndent = ' '.repeat(descriptionOffset).array;
            wrapText(output, param.description, name ~ descriptionIndent[nameLength..$], descriptionIndent);
        }
    }

    void printGroup(void delegate(string) output, const ref HelpScreen.Group group, size_t descriptionOffset)
    {
        output(group.title);
        output(":\n");

        if(group.description.getUnstyledTextLength > 0)
        {
            output("  ");
            output(group.description);
            output("\n\n");
        }

        foreach(const ref entry; group.parameters)
            printParameter(output, entry, descriptionOffset);

        output("\n");
    }

    void printHelpScreen(void delegate(string) output, const ref HelpScreen screen, size_t descriptionOffset)
    {
        output(screen.usage);
        output("\n\n");

        if(screen.description.getUnstyledTextLength > 0)
        {
            output(screen.description);
            output("\n\n");
        }

        foreach(const ref entry; screen.groups)
            printGroup(output, entry, descriptionOffset);

        if(screen.epilog.getUnstyledTextLength > 0)
        {
            output(screen.epilog);
            output("\n");
        }
    }

    // Column where the description of a parameter starts: it is aligned across all parameters but
    // parameters with an excessively long name are left out of the calculation (their description
    // starts on the next line).
    private static size_t descriptionOffset(R)(R parameters)
    {
        enum parameterNameLimit = 20;

        immutable helpPosition = 4 + parameters
            .map!(_ => _.name.getUnstyledTextLength)
            .filter!(_ => _ <= parameterNameLimit)
            .maxElement(0);

        return helpPosition + 2;
    }

    void printHelp(const CommandHelpInfo[] commands)
    {
        auto helpScreen = createHelpScreen(commands);

        printHelpScreen(sink, helpScreen, descriptionOffset(helpScreen.groups.map!((ref _) => _.parameters).joiner));
    }
}

unittest
{
    scope hp = new DefaultHelpPrinter(Config.init, Style.None, null /* unused in this test */);

    auto test(string placeholder, bool optionalValue, bool multipleOccurrence)
    {
        return hp.formatArgumentValue(ArgumentHelpInfo(
            placeholder: placeholder,
            optionalValue: optionalValue,
            multipleOccurrence: multipleOccurrence));
    }

    assert(test("", false, false) == "");
    assert(test("v", false, false) == "v");
    assert(test("v", true, false) == "[v]");
    assert(test("v", false, true) == "v ...");
    assert(test("v", true, true) == "[v ...]");
}

unittest
{
    scope hp = new DefaultHelpPrinter(Config.init, Style.None, null /* unused in this test */);

    auto test(bool optionalArgument, bool positional, bool usageString)
    {
        return hp.formatArgumentUsage(ArgumentHelpInfo(
                shortNames: ["f"],
                longNames: ["foo"],
                placeholder: "v",
                optionalArgument: optionalArgument,
                positional: positional),
        usageString);
    }

    assert(test(true, false, true) == "[-f v]");
    assert(test(true, true, true) == "[v]");
    assert(test(false, false, true) == "-f v");
    assert(test(false, true, true) == "v");

    assert(test(true, false, false) == "-f v, --foo v");
    assert(test(true, true, false) == "[v]");
    assert(test(false, false, false) == "-f v, --foo v");
    assert(test(false, true, false) == "v");
}

unittest
{
    scope hp = new DefaultHelpPrinter(Config.init, Style.None, null /* unused in this test */);

    auto test(bool usageString)
    {
        return hp.formatArgumentUsage(ArgumentHelpInfo(
                shortNames: ["f"],
                longNames: ["foo"],
                placeholder: "v",
                optionalValue: true,
                booleanFlag: true),
            usageString);
    }

    assert(test(true) == "-f");
    assert(test(false) == "-f, --[no-]foo");
}

unittest
{
    scope hp = new DefaultHelpPrinter(Config.init, Style.None, null /* unused in this test */);

    auto test(string description, Nullable!string defaultValue, bool positional = false)
    {
        return hp.formatArgumentDescription(ArgumentHelpInfo(
                description: description,
                defaultValue: defaultValue,
                positional: positional));
    }

    assert(test("desc", Nullable!string.init) == "desc");
    assert(test("", Nullable!string.init) == "");
    assert(test("desc", nullable("abc")) == "desc (default: abc)");
    assert(test("", nullable("abc")) == "(default: abc)");
    assert(test("desc", nullable("")) == "desc (default: )");
    assert(test("desc", nullable("abc"), true) == "desc (default: abc)");
}

unittest
{
    scope hp = new DefaultHelpPrinter(Config.init, Style.None, null /* unused in this test */);

    assert(hp.formatUsage([CommandHelpInfo("a"), CommandHelpInfo(name: "b", usage: "%(PROG) my usage")]) == "Usage: a b my usage");
}

unittest
{
    scope hp = new DefaultHelpPrinter(Config.init, Style.None, null /* unused in this test */);

    CommandHelpInfo cmd = {
        subCommands: [
            SubCommandHelpInfo(["cmd1"], "desc1", true),
            SubCommandHelpInfo(["cmd2","c2"], "desc2"),
        ]
    };

    auto res = hp.createSubCommandGroup(cmd);

    assert(res.title == "Available commands");
    assert(res.parameters == [
        HelpScreen.Parameter("cmd1 (default)", "desc1"),
        HelpScreen.Parameter("cmd2,c2", "desc2"),
    ]);
}

unittest
{
    string test(string s, size_t maxLineLength, string firstIndent = null, string indent = null)
    {
        auto a = appender!string;
        DefaultHelpPrinter.wrapText(_ => a.put(_), s, firstIndent, indent, maxLineLength);
        return a[];
    }
    assert(test("", 7) == "");

    assert(test("a short string", 7) == "a short\nstring\n");
    assert(test("a short string", 7, "-","+") == "-a\n+short\n+string\n");
    assert(test("a\nshort string", 7) == "a\nshort\nstring\n");

    // wrap will not break inside of a word, but at the next space
    assert(test("a short string", 4) == "a\nshort\nstring\n");

    assert(test("a short string", 7, "\t") == "\ta\nshort\nstring\n");
    assert(test("a short string", 7, "\t", "    ") == "\ta\n    short\n    string\n");
}

unittest
{
    string output;

    scope hp = new DefaultHelpPrinter(Config.init, Style.None, (_) { output ~= _; });

    ArgumentHelpInfo[] args = [
        // name is too long to fit into the name column, so the description goes to the next line
        ArgumentHelpInfo(shortNames: ["i"], longNames: ["input"], placeholder: "FILE", description: "File to read"),
        // no description at all
        ArgumentHelpInfo(shortNames: ["v"], booleanFlag: true),
        // positional argument is shown by its placeholder
        ArgumentHelpInfo(placeholder: "dest", description: "Where to upload", positional: true),
    ];

    hp.printArgumentList([]);
    assert(output == "");

    output = null;
    hp.printArgumentList(args);
    assert(output ==
        "  -i FILE, --input FILE\n"~
        "          File to read\n"~
        "  -v\n"~
        "  dest    Where to upload\n");
}
