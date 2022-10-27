module argparse.internal.utils;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Have to do this magic because closures are not supported in CFTE
// DMD v2.098.0 prints "Error: closures are not yet supported in CTFE"
package auto partiallyApply(alias fun,C...)(C context)
{
    import std.traits: ParameterTypeTuple;
    import core.lifetime: move, forward;

    return &new class(move(context))
    {
        C context;

        this(C ctx)
        {
            foreach(i, ref c; context)
                c = move(ctx[i]);
        }

        auto opCall(ParameterTypeTuple!fun[context.length..$] args) const
        {
            return fun(context, forward!args);
        }
    }.opCall;
}

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