module argparse.api.ansi;

import argparse.config;
import argparse.param;
import argparse.api.argument: NamedArgument, Description, NumberOfValues, AllowedValues, Parse, Action, ActionNoValue;
import argparse.internal.parsehelpers: PassThrough;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/// Public API for ANSI coloring
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@(NamedArgument
.Description("Colorize the output. If value is omitted then 'always' is used.")
.AllowedValues!(["always","auto","never"])
.NumberOfValues(0, 1)
.Parse!(PassThrough)
.Action!(AnsiStylingArgument.action)
.ActionNoValue!(AnsiStylingArgument.action)
)
private struct AnsiStylingArgument
{
    package(argparse) static bool isEnabled;

    public bool opCast(T : bool)() const
    {
        return isEnabled;
    }

    private static void action(ref AnsiStylingArgument receiver, RawParam param)
    {
        switch(param.value[0])
        {
            case "auto":    isEnabled = param.config.stylingMode == Config.StylingMode.on; return;
            case "always":  isEnabled = true;  return;
            case "never":   isEnabled = false; return;
            default:
        }
    }
    private static void action(ref AnsiStylingArgument receiver, Param!void param)
    {
        isEnabled = true;
    }
}

unittest
{
    AnsiStylingArgument arg;
    AnsiStylingArgument.action(arg, Param!void.init);
    assert(arg);

    AnsiStylingArgument.action(arg, RawParam(null, "", [""]));
}

unittest
{
    AnsiStylingArgument arg;

    AnsiStylingArgument.action(arg, RawParam(null, "", ["always"]));
    assert(arg);

    AnsiStylingArgument.action(arg, RawParam(null, "", ["never"]));
    assert(!arg);
}

unittest
{
    Config config;
    AnsiStylingArgument arg;

    config.stylingMode = Config.StylingMode.on;
    AnsiStylingArgument.action(arg, RawParam(&config, "", ["auto"]));
    assert(arg);

    config.stylingMode = Config.StylingMode.off;
    AnsiStylingArgument.action(arg, RawParam(&config, "", ["auto"]));
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