module argparse.helpprinter;

import argparse.helpinfo;


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/// Interface that `argparse` uses to render help text
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// This is what `Config.helpPrinterFactory` returns, so a custom implementation is used everywhere `argparse`
// formats help: the help screen, the usage line and the argument lists that appear in error messages.
// Where the text goes is decided when the printer is created - the factory receives the sink to print to.
// Note that only the functions that `argparse` calls from the outside belong here - everything that a help
// screen is built from is an implementation detail of `DefaultHelpPrinter` and stays overridable there.
public interface HelpPrinter
{
    // Prints full help screen for the provided stack of (sub)commands, starting with top-level command.
    void printHelp(const CommandHelpInfo[] commands);

    // Prints the usage line (`Usage: ...`) for the provided stack of (sub)commands.
    void printUsage(const CommandHelpInfo[] commands);

    // Prints the provided arguments rendered as they appear on help screen: name column and wrapped
    // description. Every line, including the last one, is terminated with `\n`.
    void printArgumentList(const ArgumentHelpInfo[] args);
}
