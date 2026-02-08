module argparse.internal.helpargument;

import argparse.ansi;
import argparse.config;
import argparse.helpprinter: HelpPrinter;
import argparse.helpinfo: CommandHelpInfo;
import argparse.param;
import argparse.result;
import argparse.style;
import argparse.api.ansi: ansiStylingArgument;
import argparse.internal.arguments: ArgumentInfo, Arguments, finalize;
import argparse.internal.argumentuda: ArgumentUDA;
import argparse.internal.commandinfo: CommandInfo;
import argparse.internal.lazystring;

import std.algorithm;
import std.array;


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package struct HelpArgumentUDA
{
    ArgumentInfo info;

    this(const Config config)
    {
        enum ArgumentInfo i = {
            shortNames: ["h"],
            longNames: ["help"],
            description: "Show this help message and exit",
            required: false,
            minValuesCount: 0,
            maxValuesCount: 0,
        };

        info = i.finalize!bool(config, null);
    }

    Result parse(COMMAND_STACK, RECEIVER)(const COMMAND_STACK cmdStack, ref RECEIVER receiver, RawParam param)
    {
        import std.stdio: stdout;

        auto style = ansiStylingArgument ? param.config.styling : Style.None;

        auto stack = cmdStack.map!((ref _) => _.helpInfo).array;

        if(stack[0].name.length == 0)
            stack[0].name = getProgramName(); // set command name to executable name

        if(param.config.helpPrinter)
            param.config.helpPrinter(*param.config, style, stack);
        else
        {
            scope auto output = stdout.lockingTextWriter();

            scope hp = new HelpPrinter(*param.config, style);
            hp.printHelp(_ => output.put(_), stack);
        }

        return Result.HelpWanted;
    }
}

unittest
{
    assert(HelpArgumentUDA(Config.init).info.shortNames == ["h"]);
    assert(HelpArgumentUDA(Config.init).info.longNames == ["help"]);
    assert(!HelpArgumentUDA(Config.init).info.required);
    assert(HelpArgumentUDA(Config.init).info.minValuesCount == 0);
    assert(HelpArgumentUDA(Config.init).info.maxValuesCount == 0);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) string getProgramName()
{
    import core.runtime: Runtime;
    import std.path: baseName;
    return Runtime.args[0].baseName;
}

unittest
{
    assert(getProgramName().length > 0);
}
