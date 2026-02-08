module argparse.help;

import argparse.api.ansi: ansiStylingArgument;
import argparse.config;
import argparse.helpinfo: CommandHelpInfo;
import argparse.helpprinter;
import argparse.style;
import argparse.internal.command: BasicCommand;
import argparse.internal.commandinfo: getTopLevelCommandInfo;
import argparse.internal.helpargument: getProgramName;
import argparse.internal.typetraits;

import std.meta;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private CommandHelpInfo setProgramName(CommandHelpInfo info)
{
    if(info.name.length == 0)
        info.name = getProgramName(); // set command name to executable name
    return info;
}

private template getSubCommandInfo(Config config, COMMAND, SUBCOMMAND)
{
    alias typeTraits = TypeTraits!(config, COMMAND);

    static assert(is(typeof(typeTraits.subCommands)), "There are no subcommands in "~COMMAND.stringof);

    enum findSubCommand(alias SubCommandInfo) = is(SubCommandInfo.TYPE == SUBCOMMAND);
    enum subcommands = Filter!(findSubCommand, typeTraits.subCommands);

    static assert(subcommands.length > 0, "Can't find "~SUBCOMMAND.stringof~" subcommand in "~COMMAND.stringof);
    static assert(subcommands.length == 1); // Just sanity check as we rely on distinct types of subcommands

    enum getSubCommandInfo = subcommands[0];
}

private CommandHelpInfo[] getCommandHelpInfos(Config config, COMMAND...)()
if(COMMAND.length > 0)
{
    CommandHelpInfo[] res = [
        BasicCommand!(config, COMMAND[0]).get(getTopLevelCommandInfo!(COMMAND[0])(config)).helpInfo.setProgramName
    ];

    static foreach(i; 1 .. COMMAND.length)
        res ~= BasicCommand!(config, COMMAND[i]).get(getSubCommandInfo!(config, COMMAND[i-1], COMMAND[i])).helpInfo;

    return res;
}

unittest
{
    CommandHelpInfo hi;
    assert(hi.name.length == 0);
    assert(hi.setProgramName.name.length > 0);

    hi.name = "cmd-name";
    assert(hi.setProgramName.name == "cmd-name");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

public void printHelp(Config config, COMMAND...)()
if(COMMAND.length > 0)
{
    static if(config.helpPrinter)
        config.helpPrinter(config, ansiStylingArgument ? config.styling : Style.None, getCommandHelpInfos!(config, COMMAND));
    else
    {
        import std.stdio: stdout;
        scope auto output = stdout.lockingTextWriter();

        printHelp!(config, COMMAND)(_ => output.put(_));
    }
}

public void printHelp(Config config, COMMAND...)(void delegate(string) sink)
if(COMMAND.length > 0)
{
    scope hp = new HelpPrinter(config, ansiStylingArgument ? config.styling : Style.None);
    hp.printHelp(sink, getCommandHelpInfos!(config, COMMAND));
}

unittest
{
    import argparse.api.command;
    import argparse.api.subcommand;
    import std.array: appender;

    struct B
    {
        string bs;
    }

    @Command("MYPROG")
    struct A
    {
        string as;

        SubCommand!B cmd;
    }

    enum AB_golden = "Usage: MYPROG B [--bs BS] [-h]\n\n"~
        "Optional arguments:\n"~
        "  --bs BS\n"~
        "  -h, --help    Show this help message and exit\n"~
        "  --as AS\n\n";

    auto output = appender!string;

    enum Config config = {
        styling: Style.None,
    };

    printHelp!(config, A, B)(_ => output.put(_));
    assert(output[] ==  AB_golden);
}