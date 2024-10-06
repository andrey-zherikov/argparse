module argparse.api.ansi;

import argparse.config;
import argparse.param;
import argparse.api.argument: NamedArgument, Description, NumberOfValues, AllowedValues, Parse, Action, ActionNoValue;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/// Public API for ANSI coloring
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@(NamedArgument
.Description("Colorize the output. If value is omitted then 'always' is used.")
.AllowedValues!(["always","auto","never"])
.NumberOfValues(0, 1)
.Parse((string _) => _)
.Action(AnsiStylingArgument.action)
.ActionNoValue(AnsiStylingArgument.actionNoValue)
)
private struct AnsiStylingArgument
{
    package(argparse) static bool isEnabled;

    public bool opCast(T : bool)() const
    {
        return isEnabled;
    }

    private enum action = (ref AnsiStylingArgument receiver, Param!string param)
    {
        switch(param.value)
        {
            case "auto":    isEnabled = param.config.stylingMode == Config.StylingMode.on; return;
            case "always":  isEnabled = true;  return;
            case "never":   isEnabled = false; return;
            default:
        }
    };

    private enum actionNoValue = (ref AnsiStylingArgument receiver, Param!void param)
    {
        isEnabled = true;
    };
}

unittest
{
    AnsiStylingArgument arg;
    AnsiStylingArgument.actionNoValue(arg, Param!void.init);
    assert(arg);

    AnsiStylingArgument.action(arg, Param!string(null, "", ""));
}

unittest
{
    AnsiStylingArgument arg;

    AnsiStylingArgument.action(arg, Param!string(null, "", "always"));
    assert(arg);

    AnsiStylingArgument.action(arg, Param!string(null, "", "never"));
    assert(!arg);
}

unittest
{
    Config config;
    AnsiStylingArgument arg;

    config.stylingMode = Config.StylingMode.on;
    AnsiStylingArgument.action(arg, Param!string(&config, "", "auto"));
    assert(arg);

    config.stylingMode = Config.StylingMode.off;
    AnsiStylingArgument.action(arg, Param!string(&config, "", "auto"));
    assert(!arg);
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