module argparse.helpprinter;

import argparse.helpinfo;


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/// Interface that `argparse` uses to render help text
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// This is what `Config.helpPrinterFactory` returns, so a custom implementation is used everywhere `argparse`
// formats help: the help screen, the usage line and the argument lists that appear in error messages.
// Note that only the functions that `argparse` calls from the outside belong here - everything that a help
// screen is built from is an implementation detail of `DefaultHelpPrinter` and stays overridable there.
public interface HelpPrinter
{
    // Prints full help screen for the provided stack of (sub)commands, starting with top-level command.
    // Text is passed to `sink` in pieces, as soon as they are formatted.
    void printHelp(void delegate(string) sink, CommandHelpInfo[] commands);

    // Returns the usage line (`Usage: ...`) for the last command in `commandName`.
    string formatCommandUsage(string[] commandName, in CommandHelpInfo helpInfo);

    // Returns the provided arguments rendered as they appear on help screen: name column and
    // wrapped description. Used for error messages that have to spell out which arguments they are about.
    string formatArgumentList(const ArgumentHelpInfo[] args);
}
