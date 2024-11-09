module argparse.config;

import argparse.internal.style: Style;


struct Config
{
    /**
       The assignment character used in options with parameters.
       Defaults to '='.
     */
    char assignChar = '=';

    /**
       Value separator for "--arg=value1,value2,value3" syntax
       Defaults to ','
     */
    char valueSep = ',';

    /**
       The prefix for argument name.
       Defaults to '-'.
     */
    char namedArgPrefix = '-';

    /**
       The string that conventionally marks the end of all named arguments.
       Assigning an empty string effectively disables it.
       Defaults to "--".
     */
    string endOfNamedArgs = "--";

    /**
       If set then argument names are case-sensitive.
       Defaults to true.
     */
    bool caseSensitive = true;

    package string convertCase(string str) const
    {
        import std.uni: toUpper;

        return caseSensitive ? str : str.toUpper;
    }

    /**
        Single-character arguments can be bundled together, i.e. "-abc" is the same as "-a -b -c".
        Disabled by default.
     */
    bool bundling = false;

    /**
       Add a -h/--help argument to the parser.
       Defaults to true.
     */
    bool addHelpArgument = true;

    /**
       Styling.
     */
    Style styling = Style.Default;

    /**
       Styling mode.
       Defaults to auto-detectection of the capability.
     */
    enum StylingMode { autodetect, on, off }
    StylingMode stylingMode = StylingMode.autodetect;


    /**
       Function that processes error messages if they happen during argument parsing.
       By default all errors are printed to stderr.
     */
    void function(string s) nothrow errorHandler;
}

unittest
{
    enum c = {
        Config cfg;
        cfg.errorHandler = (string s) { };
        return cfg;
    }();
}
