module argparse.internal.utils;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) string formatAllowedValues(T)(const(T)[] names)
{
    import std.format: format;
    return "{%-(%s,%)}".format(names);
}

unittest
{
    assert(formatAllowedValues(["abc", "def", "ghi"]) == "{abc,def,ghi}");
}