module argparse.api.command;

import argparse.internal.commandinfo: CommandInfo;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/// Public API for command and subcommand UDAs
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

auto Command(string[] names...)
{
    return CommandInfo(names.dup);
}

unittest
{
    auto a = Command("MYPROG");
    assert(a.names == ["MYPROG"]);
}


auto ref Usage()(auto ref CommandInfo cmd, string text)
{
    cmd.usage = text;
    return cmd;
}

auto ref Usage()(auto ref CommandInfo cmd, string function() text)
{
    cmd.usage = text;
    return cmd;
}

auto ref Description()(auto ref CommandInfo cmd, string text)
{
    cmd.description = text;
    return cmd;
}

auto ref Description()(auto ref CommandInfo cmd, string function() text)
{
    cmd.description = text;
    return cmd;
}

auto ref ShortDescription()(auto ref CommandInfo cmd, string text)
{
    cmd.shortDescription = text;
    return cmd;
}

auto ref ShortDescription()(auto ref CommandInfo cmd, string function() text)
{
    cmd.shortDescription = text;
    return cmd;
}

auto ref Epilog()(auto ref CommandInfo cmd, string text)
{
    cmd.epilog = text;
    return cmd;
}

auto ref Epilog()(auto ref CommandInfo cmd, string function() text)
{
    cmd.epilog = text;
    return cmd;
}

unittest
{
    CommandInfo c;
    c = c.Usage("usg").Description("desc").ShortDescription("sum").Epilog("epi");
    assert(c.names == []);
    assert(c.usage.get == "usg");
    assert(c.description.get == "desc");
    assert(c.shortDescription.get == "sum");
    assert(c.epilog.get == "epi");
}

unittest
{
    CommandInfo c;
    c = c.Usage(() => "usg").Description(() => "desc").ShortDescription(() => "sum").Epilog(() => "epi");
    assert(c.names == []);
    assert(c.usage.get == "usg");
    assert(c.description.get == "desc");
    assert(c.shortDescription.get == "sum");
    assert(c.epilog.get == "epi");
}
