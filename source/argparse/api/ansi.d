module argparse.api.ansi;

import argparse.config;
import argparse.param;
import argparse.api.argument: NamedArgument, Description, NumberOfValues, AllowedValues, Parse, Action, ActionNoValue;
import argparse.internal.hooks: Hooks;
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
@(Hooks.onParsingDone!(AnsiStylingArgument.finalize))
private struct AnsiStylingArgument
{
    Config.StylingMode stylingMode = Config.StylingMode.autodetect;

    alias stylingMode this;

    string toString() const
    {
        import std.conv: to;
        return stylingMode.to!string;
    }

    void set(const Config* config, Config.StylingMode mode)
    {
        config.setStylingMode(stylingMode = mode);
    }
    static void action(ref AnsiStylingArgument receiver, RawParam param)
    {
        switch(param.value[0])
        {
            case "always":  receiver.set(param.config, Config.StylingMode.on);         return;
            case "auto":    receiver.set(param.config, Config.StylingMode.autodetect); return;
            case "never":   receiver.set(param.config, Config.StylingMode.off);        return;
            default:
        }
    }
    static void action(ref AnsiStylingArgument receiver, Param!void param)
    {
        receiver.set(param.config, Config.StylingMode.on);
    }
    static void finalize(ref AnsiStylingArgument receiver, const Config* config)
    {
        receiver.set(config, config.stylingMode);
    }
}

unittest
{
    import std.conv: to;

    assert(ansiStylingArgument == AnsiStylingArgument.init);
    assert(ansiStylingArgument.toString() == Config.StylingMode.autodetect.to!string);

    Config config;
    config.setStylingModeHandlers ~= (Config.StylingMode mode) { config.stylingMode = mode; };

    AnsiStylingArgument arg;
    AnsiStylingArgument.action(arg, Param!void(&config));

    assert(config.stylingMode == Config.StylingMode.on);
    assert(arg.toString() == Config.StylingMode.on.to!string);
}

unittest
{
    auto test(string value)
    {
        Config config;
        config.setStylingModeHandlers ~= (Config.StylingMode mode) { config.stylingMode = mode; };

        AnsiStylingArgument arg;
        AnsiStylingArgument.action(arg, RawParam(&config, "", [value]));
        return config.stylingMode;
    }

    assert(test("always") == Config.StylingMode.on);
    assert(test("auto")   == Config.StylingMode.autodetect);
    assert(test("never")  == Config.StylingMode.off);
    assert(test("")       == Config.StylingMode.autodetect);
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