module argparse.api.ansi;

import argparse.ansi;
import argparse.config;
import argparse.param;
import argparse.result;
import argparse.api.argument: NamedArgument, Description, NumberOfValues, AllowedValues, Parse, Action, ActionNoValue;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/// Public API for ANSI coloring
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@(NamedArgument
.Description("Colorize the output. If value is omitted then 'always' is used.")
.AllowedValues("always","auto","never")
.NumberOfValues(0, 1)
.Parse((string _) => _)
.Action(AnsiStylingArgument.action)
.ActionNoValue(AnsiStylingArgument.actionNoValue)
)
private struct AnsiStylingArgument
{
    private static bool stdout;
    private static bool stderr;

    package(argparse) static bool stdoutStyling(bool v) { return stdout = v; }
    package(argparse) static bool stderrStyling(bool v) { return stderr = v; }

    package(argparse) static void initialize(Config.StylingMode mode)
    {
        final switch(mode)
        {
            case Config.StylingMode.on:     stdout = stderr = true;     break;
            case Config.StylingMode.off:    stdout = stderr = false;    break;
            case Config.StylingMode.autodetect:
                stdout = argparse.ansi.detectSupport(STDOUT);
                stderr = argparse.ansi.detectSupport(STDERR);
                break;
        }
    }

    //////////////////////////////////////////////////////////////////////////

    public static bool stdoutStyling() { return stdout; }
    public static bool stderrStyling() { return stderr; }

    public bool opCast(T : bool)() const
    {
        return stdoutStyling();
    }

    private enum action = (ref AnsiStylingArgument _, Param!string param)
    {
        switch(param.value)
        {
            case "always":  stdout = stderr = true;  return Result.Success;
            case "never":   stdout = stderr = false; return Result.Success;
            case "auto":
                // force detection
                stdout = argparse.ansi.detectSupport(STDOUT);
                stderr = argparse.ansi.detectSupport(STDERR);
                return Result.Success;
            default:
        }
        return Result.Success;
    };

    private enum actionNoValue = (ref AnsiStylingArgument _1, Param!void _2)
    {
        stdout = stderr = true;
        return Result.Success;
    };
}

unittest
{
    AnsiStylingArgument.initialize(Config.StylingMode.on);
    assert(ansiStylingArgument);
    assert(AnsiStylingArgument.stdoutStyling);
    assert(AnsiStylingArgument.stderrStyling);

    AnsiStylingArgument.initialize(Config.StylingMode.off);
    assert(!ansiStylingArgument);
    assert(!AnsiStylingArgument.stdoutStyling);
    assert(!AnsiStylingArgument.stderrStyling);
}

unittest
{
    AnsiStylingArgument arg;
    arg.stdoutStyling = arg.stderrStyling = false;
    AnsiStylingArgument.actionNoValue(arg, Param!void.init);
    assert(arg);
    assert(arg.stdoutStyling);
    assert(arg.stderrStyling);
}

unittest
{
    AnsiStylingArgument arg;
    arg.stdoutStyling = arg.stderrStyling = false;

    AnsiStylingArgument.action(arg, Param!string(null, "", "always"));
    assert(arg);
    assert(arg.stdoutStyling);
    assert(arg.stderrStyling);

    AnsiStylingArgument.action(arg, Param!string(null, "", "never"));
    assert(!arg);
    assert(!arg.stdoutStyling);
    assert(!arg.stderrStyling);
}

unittest
{
    AnsiStylingArgument.initialize(Config.StylingMode.autodetect);

    auto stdout = AnsiStylingArgument.stdoutStyling;
    auto stderr = AnsiStylingArgument.stderrStyling;

    AnsiStylingArgument arg;

    arg.stdoutStyling = arg.stderrStyling = true;
    AnsiStylingArgument.action(arg, Param!string(null, "", "auto"));
    assert((cast(bool) arg) == stdout);
    assert(arg.stdoutStyling == stdout);
    assert(arg.stderrStyling == stderr);

    arg.stdoutStyling = arg.stderrStyling = true;
    AnsiStylingArgument.action(arg, Param!string(null, "", "auto"));
    assert((cast(bool) arg) == stdout);
    assert(arg.stdoutStyling == stdout);
    assert(arg.stderrStyling == stderr);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

auto ansiStylingArgument()
{
    return AnsiStylingArgument.init;
}

unittest
{
    assert(ansiStylingArgument == AnsiStylingArgument.init);
}
