module argparse.internal.utils;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) string formatAllowedValues(alias names)()
{
    import std.conv: to;
    import std.array: join;
    import std.format: format;
    return "{%s}".format(names.to!(string[]).join(','));
}

unittest
{
    assert(formatAllowedValues!(["abc", "def", "ghi"]) == "{abc,def,ghi}");
}