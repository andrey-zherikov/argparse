module argparse.api.restriction;

import argparse.internal.arguments: RestrictionGroup;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/// Public API for restrictions
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Required group

auto ref Required(T : RestrictionGroup)(auto ref T group)
{
    group.required = true;
    return group;
}

unittest
{
    assert(RestrictionGroup.init.Required.required);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Arguments required together

auto RequiredTogether(string file=__FILE__, uint line = __LINE__)()
{
    import std.conv: to;
    return RestrictionGroup(file~":"~line.to!string, RestrictionGroup.Type.together);
}

unittest
{
    auto t = RequiredTogether();
    assert(t.location.length > 0);
    assert(t.type == RestrictionGroup.Type.together);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Mutually exclusive arguments

auto MutuallyExclusive(string file=__FILE__, uint line = __LINE__)()
{
    import std.conv: to;
    return RestrictionGroup(file~":"~line.to!string, RestrictionGroup.Type.exclusive);
}

unittest
{
    auto e = MutuallyExclusive();
    assert(e.location.length > 0);
    assert(e.type == RestrictionGroup.Type.exclusive);
}
