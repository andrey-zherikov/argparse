module argparse.api.argumentgroup;

import argparse.internal.arguments: Group;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/// Public API for argument group UDA
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Group of arguments

auto ArgumentGroup(string name)
{
    return Group(name);
}

auto ref Description()(auto ref Group group, string text)
{
    group.description = text;
    return group;
}

auto ref Description()(auto ref Group group, string function() text)
{
    group.description = text;
    return group;
}

unittest
{
    auto g = ArgumentGroup("name").Description("description");
    assert(g.name == "name");
    assert(g.description.get == "description");

    g = g.Description(() => "descr");
    assert(g.description.get == "descr");
}

