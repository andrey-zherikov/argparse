import argparse;

// Custom help printer that puts every argument name in square brackets.
// Only one function is overridden, yet it changes the help screen, the usage line and
// the lists of arguments in error messages.
static class MyHelpPrinter : DefaultHelpPrinter
{
    this(const Config config, Style style)
    {
        super(config, style);
    }

    override string formatArgumentUsage(in ArgumentHelpInfo helpInfo, bool usageString)
    {
        return "[" ~ super.formatArgumentUsage(helpInfo, usageString) ~ "]";
    }
}

struct T
{
    string a;
}

enum Config cfg = {
    helpPrinterFactory: (config, style) => new MyHelpPrinter(config, style)
};

T t;
assert(!CLI!(cfg, T).parseArgs(t, ["-h"]));
