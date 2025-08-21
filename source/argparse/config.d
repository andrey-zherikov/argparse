module argparse.config;

import argparse.internal.style: Style;


struct Config
{
    /**
       The assignment character used in arguments with parameters.
       Defaults to '='.
     */
    char assignChar = '=';

    /**
       The assignment character used in "key=value" syntax for arguments that have associative array type.
       Defaults to '='.
     */
    char assignKeyValueChar = '=';

    /**
       Value separator for "--arg=value1,value2,value3" syntax
       Defaults to ','
     */
    char valueSep = ',';

    /**
       The prefix for short argument name.
       Defaults to "-".
     */
    string shortNamePrefix = "-";

    /**
       The prefix for long argument name.
       Defaults to "--".
     */
    string longNamePrefix = "--";

    /**
       The string that conventionally marks the end of all named arguments.
       Assigning an empty string effectively disables it.
       Defaults to "--".
     */
    string endOfNamedArgs = "--";

    /**
       If set then argument short names are case-sensitive.
       Defaults to true.
     */
    bool caseSensitiveShortName  = true;

    /**
       If set then argument long names are case-sensitive.
       Defaults to true.
     */
    bool caseSensitiveLongName   = true;

    /**
       If set then subcommands are case-sensitive.
       Defaults to true.
     */
    bool caseSensitiveSubCommand = true;

    /**
       Helper to set all case sensitivity settings to a specific value
     */
    void caseSensitive(bool value) { caseSensitiveShortName = caseSensitiveLongName = caseSensitiveSubCommand = value; }

    /**
        Single-character arguments can be bundled together, i.e. "-abc" is the same as "-a -b -c".
        Disabled by default.
     */
    bool bundling = false;

    /**
        By default, consume one value per appearance of named argument in command line.
        With `variadicNamedArgument` enabled (as was the default in v1), named arguments will
        consume all named arguments up to the next named argument if the receiving field is an array.
     */
    bool variadicNamedArgument = false;

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

    /**
       Exit code that is returned from main() in case of parsing error.
       Defaults to 1.
     */
    int errorExitCode = 1;
}

unittest
{
    enum c = {
        Config cfg;
        cfg.errorHandler = (string s) { };
        return cfg;
    }();
}

unittest
{
    Config cfg;
    assert(cfg.caseSensitiveShortName);
    assert(cfg.caseSensitiveLongName);
    assert(cfg.caseSensitiveSubCommand);
    cfg.caseSensitive = false;
    assert(!cfg.caseSensitiveShortName);
    assert(!cfg.caseSensitiveLongName);
    assert(!cfg.caseSensitiveSubCommand);
    cfg.caseSensitive = true;
    assert(cfg.caseSensitiveShortName);
    assert(cfg.caseSensitiveLongName);
    assert(cfg.caseSensitiveSubCommand);
}
