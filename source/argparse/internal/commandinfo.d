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
    bool isDefaultSubCommand = false;
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private auto finalize(const Config config, CommandInfo info, bool isDefaultSubCommand)
{
    info.displayNames = info.names.dup;

    info.caseSensitive = config.caseSensitiveSubCommand;
    if(!config.caseSensitiveSubCommand)
    {
        import std.algorithm: each;
        import std.uni : toUpper;

        info.names.each!((ref _) => _ = _.toUpper);
    }
    
    info.isDefaultSubCommand = isDefaultSubCommand;

    return info;
}

unittest
{
    auto info = finalize(Config.init, CommandInfo(["cmd-Name"]), false);
    assert(info.displayNames == ["cmd-Name"]);
    assert(info.names == ["cmd-Name"]);
    assert(!info.isDefaultSubCommand);
}

unittest
{
    enum Config config = { caseSensitiveShortName: false, caseSensitiveLongName: false, caseSensitiveSubCommand: false };

    auto info = finalize(config, CommandInfo(["cmd-Name"]), true);
    assert(info.displayNames == ["cmd-Name"]);
    assert(info.names == ["CMD-NAME"]);
    assert(info.isDefaultSubCommand);
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

package auto getSubCommandInfo(COMMAND)(Config config, bool isDefault)
{
    struct SubCommand
    {
        CommandInfo info;
        alias info this;

        bool isDefault;

        alias TYPE = COMMAND;
    }

    CommandInfo info = getCommandInfo!COMMAND;

    if(info.names.length == 0)
        info.names = [COMMAND.stringof];

    return SubCommand(finalize(config, info, isDefault), isDefault);
}

package(argparse) CommandInfo getTopLevelCommandInfo(COMMAND)(Config config)
{
    return finalize(config, getCommandInfo!COMMAND, false);
}

unittest
{
    @CommandInfo()
    struct T {}

    auto sc = getSubCommandInfo!T(Config.init, false);
    assert(sc.displayNames == ["T"]);
    assert(sc.names == ["T"]);
    assert(!sc.isDefault);
    assert(is(sc.TYPE == T));

    sc = getSubCommandInfo!T(Config.init, true);
    assert(sc.displayNames == ["T"]);
    assert(sc.names == ["T"]);
    assert(sc.isDefault);
    assert(is(sc.TYPE == T));
}