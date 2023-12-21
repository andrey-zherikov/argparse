module argparse.internal.commandinfo;

import argparse.config;
import argparse.internal.lazystring;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) struct CommandInfo
{
    string[] names = [""];
    string[] displayNames;
    LazyString usage;
    LazyString description;
    LazyString shortDescription;
    LazyString epilog;
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private auto finalize(const Config config, CommandInfo uda)
{
    uda.displayNames = uda.names.dup;

    if(!config.caseSensitive)
    {
        import std.algorithm: each;
        uda.names.each!((ref _) => _ = config.convertCase(_));
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
    enum config = {
        Config config;
        config.caseSensitive = false;
        return config;
    }();

    auto uda = finalize(config, CommandInfo(["cmd-Name"]));
    assert(uda.displayNames == ["cmd-Name"]);
    assert(uda.names == ["CMD-NAME"]);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) CommandInfo getCommandInfo(COMMAND)(const Config config, string name = "")
{
    import std.traits: getUDAs;

    enum udas = getUDAs!(COMMAND, CommandInfo);
    static assert(udas.length <= 1, COMMAND.stringof~" has multiple @Command UDA");

    static if(udas.length > 0)
    {
        CommandInfo info = udas[0];

        if(name.length > 0 && info.names.length == 0)
            info.names = [name];

        info = finalize(config, info);
    }
    else
        CommandInfo info = finalize(config, CommandInfo([name]));

    assert(name == "" || info.names.length > 0 && info.names[0].length > 0, "Command "~COMMAND.stringof~" must have name");
    return info;
}

unittest
{
    @(CommandInfo([]))
    struct T {}

    auto info = getCommandInfo!T(Config.init, "t");
    assert(info.displayNames == ["t"]);
    assert(info.names == ["t"]);
}