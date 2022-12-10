module argparse.api;

import argparse.internal.style: Style;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/// Public API
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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
       The option character.
       Defaults to '-'.
     */
    char namedArgChar = '-';

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
       Styling and coloring mode.
       Defaults to auto-detectection of the capability.
     */
    enum StylingMode { autodetect, on, off }
    StylingMode stylingMode = StylingMode.autodetect;

    package void delegate(StylingMode)[] setStylingModeHandlers;
    package void setStylingMode(StylingMode mode) const
    {
        foreach(dg; setStylingModeHandlers)
            dg(mode);
    }

    /**
       Help style.
     */
    Style helpStyle = Style.Default;

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


    package void onError(string message) const nothrow
    {
        import std.stdio: stderr, writeln;

        try
        {
            if(errorHandlerFunc)
                errorHandlerFunc(message);
            else
                stderr.writeln("Error: ", message);
        }
        catch(Exception e)
        {
            throw new Error(e.msg);
        }
    }
}

unittest
{
    enum text = "--just testing error func--";

    bool called = false;

    Config c;
    c.errorHandler = (string s)
    {
        assert(s == text);
        called = true;
    };
    c.onError(text);
    assert(called);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

struct Param(VALUE_TYPE)
{
    const Config* config;
    string name;

    static if(!is(VALUE_TYPE == void))
        VALUE_TYPE value;
}

alias RawParam = Param!(string[]);

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

struct Result
{
    int  resultCode;

    package enum Status { failure, success, unknownArgument };
    package Status status;

    package string errorMsg;

    package const(string)[] suggestions;

    package static enum Failure = Result(1, Status.failure);
    package static enum Success = Result(0, Status.success);
    package static enum UnknownArgument = Result(0, Status.unknownArgument);

    bool opCast(T : bool)() const
    {
        return status == Status.success;
    }

    package static auto Error(A...)(A args)
    {
        import std.conv: text;

        return Result(1, Status.failure, text!A(args));
    }

    version(unittest)
    {
        package bool isError(string text)
        {
            import std.algorithm: canFind;
            return (!cast(bool) this) && errorMsg.canFind(text);
        }
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Default subcommand
struct Default(COMMAND)
{
    COMMAND command;
    alias command this;
}

package enum isDefault(T) = is(T == Default!ORIG_TYPE, ORIG_TYPE);

package alias RemoveDefault(T : Default!ORIG_TYPE, ORIG_TYPE) = ORIG_TYPE;
package alias RemoveDefault(T) = T;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////