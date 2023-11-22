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

private auto finalize(Config config, alias initUDA)()
{
    auto uda = initUDA;

    uda.displayNames = uda.names.dup;

    static if(!config.caseSensitive)
    {
        import std.algorithm: each;
        uda.names.each!((ref _) => _ = config.convertCase(_));
    }

    return uda;
}

unittest
{
    auto uda = finalize!(Config.init, CommandInfo(["cmd-Name"]));
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

    auto uda = finalize!(config, CommandInfo(["cmd-Name"]));
    assert(uda.displayNames == ["cmd-Name"]);
    assert(uda.names == ["CMD-NAME"]);
}

package(argparse) template getCommandInfo(Config config, COMMAND, string name = "")
{
    import std.traits: getUDAs;

    enum udas = getUDAs!(COMMAND, CommandInfo);
    static assert(udas.length <= 1, COMMAND.stringof~" has multiple @Command UDA");

    static if(udas.length > 0)
        enum getCommandInfo = finalize!(config, udas[0]);
    else
        enum getCommandInfo = finalize!(config, CommandInfo([name]));

    static assert(name == "" || getCommandInfo.names.length > 0 && getCommandInfo.names[0].length > 0, "Command "~COMMAND.stringof~" must have name");
}