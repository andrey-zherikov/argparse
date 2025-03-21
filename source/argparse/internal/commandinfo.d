module argparse.internal.commandinfo;

import argparse.config;
import argparse.internal.lazystring;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) struct CommandInfo
{
    string[] names;
    string[] displayNames;
    bool caseSensitive = true;
    LazyString usage;
    LazyString description;
    LazyString shortDescription;
    LazyString epilog;
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private auto finalize(const Config config, CommandInfo uda)
{
    uda.displayNames = uda.names.dup;

    uda.caseSensitive = config.caseSensitiveSubCommand;
    if(!config.caseSensitiveSubCommand)
    {
        import std.algorithm: each;
        import std.uni : toUpper;

        uda.names.each!((ref _) => _ = _.toUpper);
    }

    return uda;
}

unittest
{
    auto uda = finalize(Config.init, CommandInfo(["cmd-Name"]));
    assert(uda.displayNames == ["cmd-Name"]);
    assert(uda.names == ["cmd-Name"]);
}

unittest
{
    enum Config config = { caseSensitiveShortName: false, caseSensitiveLongName: false, caseSensitiveSubCommand: false };

    auto uda = finalize(config, CommandInfo(["cmd-Name"]));
    assert(uda.displayNames == ["cmd-Name"]);
    assert(uda.names == ["CMD-NAME"]);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private template getCommandInfo(TYPE)
{
    import std.traits: getUDAs;

    enum udas = getUDAs!(TYPE, CommandInfo);
    static assert(udas.length <= 1, TYPE.stringof~" has multiple @Command UDA");

    static if(udas.length > 0)
        enum getCommandInfo = udas[0];
    else
        enum getCommandInfo = CommandInfo.init;
}

package(argparse) CommandInfo getSubCommandInfo(COMMAND)(const Config config)
{
    CommandInfo info = getCommandInfo!COMMAND;

    if(info.names.length == 0)
        info.names = [COMMAND.stringof];

    return finalize(config, info);
}

package(argparse) CommandInfo getTopLevelCommandInfo(COMMAND)(const Config config)
{
    return finalize(config, getCommandInfo!COMMAND);
}

unittest
{
    @CommandInfo()
    struct T {}

    auto info = getSubCommandInfo!T(Config.init);
    assert(info.displayNames == ["T"]);
    assert(info.names == ["T"]);
}