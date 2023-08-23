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
       The string that conventionally marks the end of all options.
       Assigning an empty string to `endOfArgs` effectively disables it.
       Defaults to "--".
     */
    string endOfArgs = "--";

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
       Delegate that processes error messages if they happen during argument parsing.
       By default all errors are printed to stderr.
     */
    package void delegate(string s) nothrow errorHandlerFunc;

    @property auto errorHandler(void function(string s) nothrow func)
    {
        return errorHandlerFunc = (string msg) { func(msg); };
    }

    @property auto errorHandler(void delegate(string s) nothrow func)
    {
        return errorHandlerFunc = func;
    }
}

unittest
{
    auto f = function(string s) nothrow {};

    Config c;
    assert(!c.errorHandlerFunc);
    assert((c.errorHandler = f));
    assert(c.errorHandlerFunc);
}

unittest
{
    auto f = delegate(string s) nothrow {};

    Config c;
    assert(!c.errorHandlerFunc);
    assert((c.errorHandler = f) == f);
    assert(c.errorHandlerFunc == f);
}