module argparse.helpprinter;

import argparse.helpinfo;
import argparse.style;

import std.algorithm;
import std.conv: text;
import std.range;
import std.string;

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

public class HelpPrinter
{
    Style style;

    this(Style s)
    {
        style = s;
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
        auto value = formatArgumentValue(helpInfo);

        if(helpInfo.positional)
            return wrapOptional(helpInfo.optionalArgument, value);

        if(value.length > 0)
            value = " " ~ value; // prepend with space

        alias formatNameAndValue = _ => style.argumentName(_) ~ value;

        if(usageString)
        {
            // usage string contains only one agrument name (even if it has multiple names) and
            // includes square brackets '[]' if argument is optional
            return wrapOptional(helpInfo.optionalArgument, formatNameAndValue(helpInfo.names[0]));
        }
        else
        {
            // argument description doesn't contain square brackets '[]' even when argument is optional
            // but shows all argument names
            return helpInfo.names.map!formatNameAndValue.join(", ");
        }
    }

    string formatCommandUsage(string[] commandName, in CommandHelpInfo helpInfo)
    {
        string usage;

        if(helpInfo.usage.length > 0)
            usage = replace(helpInfo.usage, "%(PROG)", commandName.join(" "));
        else
        {
            usage = chain(
                    commandName,
                    helpInfo.namedArguments.map!((ref _) => formatArgumentUsage(_, true)),       // named arguments
                    helpInfo.positionalArguments.map!((ref _) => formatArgumentUsage(_, true)),  // positional arguments
                    helpInfo.subCommands.length > 0 ? ["<command> [<args>]"] : []          // subcommands if any
                ).join(" ");
        }
        return "Usage: " ~ usage;
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
                    HelpScreen.Parameter(_.names.map!(_ => style.subcommandName(_)).join(","), _.description))
                .array
        );
    }

    HelpScreen.Group[] createArgumentsGroups(const ref CommandHelpInfo[] commands)
    {
        bool[string] processedArgs;

        alias showArg = (_) =>
            !_.hidden && !(_.names[0] in processedArgs) ? (processedArgs[_.names[0]] = true) : false;


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
                    .map!(_ => HelpScreen.Parameter(formatArgumentUsage(_, false), _.description))
                    .array;
            }
        }

        return groups;
    }

    HelpScreen createHelpScreen(CommandHelpInfo[] commands)
    {
        auto ref currentCmd = commands[$-1];

        auto cmdFullName = commands.map!((ref _) => _.name).array;

        auto helpScreen = HelpScreen(formatCommandUsage(cmdFullName, currentCmd),
                                     currentCmd.description,
                                     currentCmd.epilog);

        // sub commands go first
        if(currentCmd.subCommands.length > 0)
            helpScreen.groups ~= createSubCommandGroup(currentCmd);

        // then arguments
        helpScreen.groups ~= createArgumentsGroups(commands);

        return helpScreen;
    }

    ///////////////////////////////////////////////////////////////////////////
    // Printing functions
    ///////////////////////////////////////////////////////////////////////////

    void printParameter(void delegate(string) sink, const ref HelpScreen.Parameter param, size_t descriptionOffset)
    {
        string name = "  " ~ param.name;
        auto nameLength = name.getUnstyledTextLength();

        if(param.description.getUnstyledTextLength == 0)
        {
            sink(name);
            sink("\n");
        }
        else if(nameLength + 2 > descriptionOffset) // 2 = two spaces between name and description
        {
            // long name; start description on the next line
            sink(name);
            sink("\n");

            immutable descriptionIndent = ' '.repeat(descriptionOffset).array;
            wrapText(sink, param.description, descriptionIndent, descriptionIndent);
        }
        else
        {
            // name is short enough to fit before the description on the first line
            // to render this correctly, we put name into first-line indent parameter

            immutable descriptionIndent = ' '.repeat(descriptionOffset).array;
            wrapText(sink, param.description, name ~ descriptionIndent[nameLength..$], descriptionIndent);
        }
    }

    void printGroup(void delegate(string) sink, const ref HelpScreen.Group group, size_t descriptionOffset)
    {
        sink(group.title);
        sink(":\n");

        if(group.description.getUnstyledTextLength > 0)
        {
            sink("  ");
            sink(group.description);
            sink("\n\n");
        }

        foreach(const ref entry; group.parameters)
            printParameter(sink, entry, descriptionOffset);

        sink("\n");
    }

    void printHelpScreen(void delegate(string) sink, const ref HelpScreen screen, size_t descriptionOffset)
    {
        sink(screen.usage);

        sink("\n\n");

        if(screen.description.getUnstyledTextLength > 0)
        {
            sink(screen.description);
            sink("\n\n");
        }

        foreach(const ref entry; screen.groups)
            printGroup(sink, entry, descriptionOffset);

        if(screen.epilog.getUnstyledTextLength > 0)
        {
            sink(screen.epilog);
            sink("\n");
        }
    }

    void printHelp(void delegate(string) sink, CommandHelpInfo[] commands)
    {
        auto helpScreen = createHelpScreen(commands);

        enum parameterNameLimit = 20;

        immutable helpPosition = 4 + helpScreen.groups
            .map!((ref _) => _.parameters.map!((ref _) => _.name.getUnstyledTextLength))
            .joiner
            .filter!(_ => _ <= parameterNameLimit)
            .maxElement(0);

        printHelpScreen(sink, helpScreen, helpPosition + 2);
    }
}

unittest
{
    scope hp = new HelpPrinter(Style.None);

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
    scope hp = new HelpPrinter(Style.None);

    auto test(bool optionalArgument, bool positional)
    {
        return hp.formatArgumentUsage(ArgumentHelpInfo(
                names: ["-f","--foo"],
                placeholder: "v",
                optionalArgument: optionalArgument,
                positional: positional),
            true);
    }

    assert(test(true, false) == "[-f v]");
    assert(test(true, true) == "[v]");
    assert(test(false, false) == "-f v");
    assert(test(false, true) == "v");
}

unittest
{
    scope hp = new HelpPrinter(Style.None);
    auto res = hp.formatCommandUsage(["a","b"], CommandHelpInfo(usage: "%(PROG) my usage"));

    assert(res == "Usage: a b my usage");
}

unittest
{
    string test(string s, size_t maxLineLength, string firstIndent = null, string indent = null)
    {
        auto a = appender!string;
        HelpPrinter.wrapText(_ => a.put(_), s, firstIndent, indent, maxLineLength);
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
