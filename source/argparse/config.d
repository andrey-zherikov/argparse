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
       When set to char.init, parameters to array and associative array receivers are
       treated as an individual argument. That is, only one argument is appended or
       inserted per appearance of the option switch. If `arraySep` is set to
       something else, then each parameter is first split by the separator, and the
       individual pieces are treated as arguments to the same option.

       Defaults to char.init
     */
    char arraySep = char.init;

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
        Single-letter arguments can be bundled together, i.e. "-abc" is the same as "-a -b -c".
        Disabled by default.
     */
    bool bundling = false;

    /**
       Add a -h/--help option to the parser.
       Defaults to true.
     */
    bool addHelp = true;

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
