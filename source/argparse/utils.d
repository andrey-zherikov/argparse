module argparse.utils;

import argparse;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/// Assorted helpers
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package template EnumMembersAsStrings(E)
{
    enum EnumMembersAsStrings = {
        import std.traits: EnumMembers;
        alias members = EnumMembers!E;

        typeof(__traits(identifier, members[0]))[] res;
        static foreach (i, _; members)
            res ~= __traits(identifier, members[i]);

        return res;
    }();
}

unittest
{
    enum E { abc, def, ghi }
    assert(EnumMembersAsStrings!E == ["abc", "def", "ghi"]);
}

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

package string getProgramName()
{
    import core.runtime: Runtime;
    import std.path: baseName;
    return Runtime.args[0].baseName;
}

unittest
{
    assert(getProgramName().length > 0);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package mixin template ForwardMemberFunction(string dest)
{
    import std.array: split;
    mixin("auto "~dest.split('.')[$-1]~"(Args...)(auto ref Args args) inout { import core.lifetime: forward; return "~dest~"(forward!args); }");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package void substituteProg(Output)(auto ref Output output, string text, string prog)
{
    import std.array: replaceInto;
    output.replaceInto(text, "%(PROG)", prog);
}

unittest
{
    import std.array: appender;
    auto a = appender!string;
    a.substituteProg("this is some text where %(PROG) is substituted but PROG and prog are not", "-myprog-");
    assert(a[] == "this is some text where -myprog- is substituted but PROG and prog are not");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package string spaces(ulong num)
{
    import std.range: repeat;
    import std.array: array;
    return ' '.repeat(num).array;
}

unittest
{
    assert(spaces(0) == "");
    assert(spaces(1) == " ");
    assert(spaces(5) == "     ");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package void wrapMutiLine(Output, S)(auto ref Output output,
                                     S s,
                                     in size_t columns = 80,
                                     S firstindent = null,
                                     S indent = null,
                                     in size_t tabsize = 8)
{
    import std.string: wrap, lineSplitter, join;
    import std.algorithm: map, copy;

    auto lines = s.lineSplitter;
    if(lines.empty)
    {
        output.put(firstindent);
        output.put("\n");
        return;
    }

    output.put(lines.front.wrap(columns, firstindent, indent, tabsize));
    lines.popFront;

    lines.map!(s => s.wrap(columns, indent, indent, tabsize)).copy(output);
}

unittest
{
    string test(string s, size_t columns, string firstindent = null, string indent = null)
    {
        import std.array: appender;
        auto a = appender!string;
        a.wrapMutiLine(s, columns, firstindent, indent);
        return a[];
    }
    assert(test("a short string", 7) == "a short\nstring\n");
    assert(test("a\nshort string", 7) == "a\nshort\nstring\n");

    // wrap will not break inside of a word, but at the next space
    assert(test("a short string", 4) == "a\nshort\nstring\n");

    assert(test("a short string", 7, "\t") == "\ta\nshort\nstring\n");
    assert(test("a short string", 7, "\t", "    ") == "\ta\n    short\n    string\n");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package auto consumeValuesFromCLI(ref string[] args, in ArgumentInfo argumentInfo, in Config config)
{
    import std.range: empty, front, popFront;

    immutable minValuesCount = argumentInfo.minValuesCount.get;
    immutable maxValuesCount = argumentInfo.maxValuesCount.get;

    string[] values;

    if(minValuesCount > 0)
    {
        if(minValuesCount < args.length)
        {
            values = args[0..minValuesCount];
            args = args[minValuesCount..$];
        }
        else
        {
            values = args;
            args = [];
        }
    }

    while(!args.empty &&
    values.length < maxValuesCount &&
    (args.front.length == 0 || args.front[0] != config.namedArgChar))
    {
        values ~= args.front;
        args.popFront();
    }

    return values;
}

