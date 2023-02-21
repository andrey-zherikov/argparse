module argparse.api.enums;

import argparse.internal.enumhelpers: EnumValue;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/// Public API for enums
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

auto ArgumentValue(string[] name...)
{
    return EnumValue(name.dup);
}

unittest
{
    assert(ArgumentValue("a","b").values == ["a","b"]);
}