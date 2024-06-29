module argparse.api.argument;

import argparse.param;
import argparse.result;

import argparse.internal.arguments: ArgumentInfo;
import argparse.internal.argumentuda: ArgumentUDA;
import argparse.internal.valueparser: ValueParser;
import argparse.internal.parsehelpers: ValueInList;
import argparse.internal.utils: formatAllowedValues;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/// Public API for argument UDA
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

auto ref Description(T)(auto ref ArgumentUDA!T uda, string text)
{
    uda.info.description = text;
    return uda;
}

auto ref Description(T)(auto ref ArgumentUDA!T uda, string function() text)
{
    uda.info.description = text;
    return uda;
}

auto ref Required(T)(auto ref ArgumentUDA!T uda)
{
    uda.info.required = true;
    return uda;
}

auto ref Optional(T)(auto ref ArgumentUDA!T uda)
{
    uda.info.required = false;
    return uda;
}

auto ref HideFromHelp(T)(auto ref ArgumentUDA!T uda, bool hide = true)
{
    uda.info.hideFromHelp = hide;
    return uda;
}

auto ref Placeholder(T)(auto ref ArgumentUDA!T uda, string value)
{
    uda.info.placeholder = value;
    return uda;
}

auto ref NumberOfValues(T)(auto ref ArgumentUDA!T uda, size_t num)
{
    uda.info.minValuesCount = num;
    uda.info.maxValuesCount = num;
    return uda;
}

auto ref NumberOfValues(T)(auto ref ArgumentUDA!T uda, size_t min, size_t max)
{
    uda.info.minValuesCount = min;
    uda.info.maxValuesCount = max;
    return uda;
}

auto ref MinNumberOfValues(T)(auto ref ArgumentUDA!T uda, size_t min)
{
    assert(min <= uda.info.maxValuesCount.get(size_t.max));

    uda.info.minValuesCount = min;
    return uda;
}

auto ref MaxNumberOfValues(T)(auto ref ArgumentUDA!T uda, size_t max)
{
    assert(max >= uda.info.minValuesCount.get(0));

    uda.info.maxValuesCount = max;
    return uda;
}


unittest
{
    ArgumentUDA!void arg;
    assert(!arg.info.hideFromHelp);
    assert(!arg.info.required);
    assert(arg.info.minValuesCount.isNull);
    assert(arg.info.maxValuesCount.isNull);

    arg = arg.Description("desc").Placeholder("text");
    assert(arg.info.description.get == "desc");
    assert(arg.info.placeholder == "text");

    arg = arg.Description(() => "qwer").Placeholder("text");
    assert(arg.info.description.get == "qwer");

    arg = arg.HideFromHelp.Required.NumberOfValues(10);
    assert(arg.info.hideFromHelp);
    assert(arg.info.required);
    assert(arg.info.minValuesCount.get == 10);
    assert(arg.info.maxValuesCount.get == 10);

    arg = arg.Optional.NumberOfValues(20,30);
    assert(!arg.info.required);
    assert(arg.info.minValuesCount.get == 20);
    assert(arg.info.maxValuesCount.get == 30);

    arg = arg.MinNumberOfValues(2).MaxNumberOfValues(3);
    assert(arg.info.minValuesCount.get == 2);
    assert(arg.info.maxValuesCount.get == 3);

    // values shouldn't be changed
    arg.addDefaults(ArgumentUDA!void.init);
    assert(arg.info.placeholder == "text");
    assert(arg.info.description.get == "qwer");
    assert(arg.info.hideFromHelp);
    assert(!arg.info.required);
    assert(arg.info.minValuesCount.get == 2);
    assert(arg.info.maxValuesCount.get == 3);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

auto PositionalArgument(uint position)
{
    auto arg = ArgumentUDA!(ValueParser!(void, void, void, void, void, void))(ArgumentInfo.init).Required();
    arg.info.position = position;
    return arg;
}

auto PositionalArgument(uint position, string placeholder)
{
    return PositionalArgument(position).Placeholder(placeholder);
}

auto NamedArgument(string[] names...)
{
    return ArgumentUDA!(ValueParser!(void, void, void, void, void, void))(ArgumentInfo(names.dup)).Optional();
}

unittest
{
    auto arg = PositionalArgument(3, "foo");
    assert(arg.info.required);
    assert(arg.info.positional);
    assert(arg.info.position == 3);
    assert(arg.info.placeholder == "foo");
}

unittest
{
    auto arg = NamedArgument("foo");
    assert(!arg.info.required);
    assert(!arg.info.positional);
    assert(arg.info.shortNames == ["foo"]);
}

unittest
{
    auto arg = NamedArgument(["foo","bar"]);
    assert(!arg.info.required);
    assert(!arg.info.positional);
    assert(arg.info.shortNames == ["foo","bar"]);
}

unittest
{
    auto arg = NamedArgument("foo","bar");
    assert(!arg.info.required);
    assert(!arg.info.positional);
    assert(arg.info.shortNames == ["foo","bar"]);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

auto AllowNoValue(alias valueToUse, T)(ArgumentUDA!T uda)
{
    return uda.ActionNoValue!(() => valueToUse);
}

auto RequireNoValue(alias valueToUse, T)(ArgumentUDA!T uda)
{
    auto desc = uda.AllowNoValue!valueToUse;
    desc.info.minValuesCount = 0;
    desc.info.maxValuesCount = 0;
    return desc;
}

unittest
{
    auto uda = NamedArgument.AllowNoValue!({});
    assert(is(typeof(uda) : ArgumentUDA!(ValueParser!(void, void, void, void, void, FUNC)), alias FUNC));
    assert(!is(FUNC == void));
    assert(uda.info.minValuesCount == 0);
}

unittest
{
    auto uda = NamedArgument.RequireNoValue!"value";
    assert(is(typeof(uda) : ArgumentUDA!(ValueParser!(void, void, void, void, void, FUNC)), alias FUNC));
    assert(!is(FUNC == void));
    assert(uda.info.minValuesCount == 0);
    assert(uda.info.maxValuesCount == 0);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/// Parsing customization

auto PreValidation(alias func, T)(ArgumentUDA!T uda)
{
    return ArgumentUDA!(uda.parsingFunc.changePreValidation!func)(uda.tupleof);
}

auto Parse(alias func, T)(ArgumentUDA!T uda)
{
    auto desc = ArgumentUDA!(uda.parsingFunc.changeParse!func)(uda.tupleof);

    static if(__traits(compiles, { func(string.init); }))
        desc.info.minValuesCount = desc.info.maxValuesCount = 1;
    else
    {
        desc.info.minValuesCount = 0;
        desc.info.maxValuesCount = size_t.max;
    }

    return desc;
}

auto Validation(alias func, T)(ArgumentUDA!T uda)
{
    return ArgumentUDA!(uda.parsingFunc.changeValidation!func)(uda.tupleof);
}

auto Action(alias func, T)(ArgumentUDA!T uda)
{
    return ArgumentUDA!(uda.parsingFunc.changeAction!func)(uda.tupleof);
}

auto ActionNoValue(alias func, T)(ArgumentUDA!T uda)
{
    auto desc = ArgumentUDA!(uda.parsingFunc.changeNoValueAction!func)(uda.tupleof);
    desc.info.minValuesCount = 0;
    return desc;
}


unittest
{
    auto uda = NamedArgument.PreValidation!({});
    assert(is(typeof(uda) : ArgumentUDA!(ValueParser!(void, FUNC, void, void, void, void)), alias FUNC));
    assert(!is(FUNC == void));
}

unittest
{
    auto uda = NamedArgument.Parse!({});
    assert(is(typeof(uda) : ArgumentUDA!(ValueParser!(void, void, FUNC, void, void, void)), alias FUNC));
    assert(!is(FUNC == void));
}

unittest
{
    auto uda = NamedArgument.Parse!((string _) => _);
    assert(is(typeof(uda) : ArgumentUDA!(ValueParser!(void, void, FUNC, void, void, void)), alias FUNC));
    assert(!is(FUNC == void));
    assert(uda.info.minValuesCount == 1);
    assert(uda.info.maxValuesCount == 1);
}

unittest
{
    auto uda = NamedArgument.Parse!((string[] _) => _);
    assert(is(typeof(uda) : ArgumentUDA!(ValueParser!(void, void, FUNC, void, void, void)), alias FUNC));
    assert(!is(FUNC == void));
    assert(uda.info.minValuesCount == 0);
    assert(uda.info.maxValuesCount == size_t.max);
}

unittest
{
    auto uda = NamedArgument.Validation!({});
    assert(is(typeof(uda) : ArgumentUDA!(ValueParser!(void, void, void, FUNC, void, void)), alias FUNC));
    assert(!is(FUNC == void));
}

unittest
{
    auto uda = NamedArgument.Action!({});
    assert(is(typeof(uda) : ArgumentUDA!(ValueParser!(void, void, void, void, FUNC, void)), alias FUNC));
    assert(!is(FUNC == void));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


auto AllowedValues(alias values, T)(ArgumentUDA!T uda)
{
    import std.array : assocArray;
    import std.range : repeat;
    import std.traits: KeyType;

    enum valuesAA = assocArray(values, false.repeat);

    auto desc = uda.Validation!(ValueInList!(values, KeyType!(typeof(valuesAA))));
    if(desc.info.placeholder.length == 0)
        desc.info.placeholder = formatAllowedValues(values);

    return desc;
}

unittest
{
    assert(NamedArgument.AllowedValues!([1, 3, 5]).info.placeholder == "{1,3,5}");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private struct CounterParsingFunction
{
    static Result parse(T)(ref T receiver, const ref RawParam param)
    {
        assert(param.value.length == 0);

        ++receiver;

        return Result.Success;
    }
}

auto Counter(T)(ArgumentUDA!T uda)
{
    auto desc = ArgumentUDA!CounterParsingFunction(uda.tupleof);
    desc.info.minValuesCount = 0;
    desc.info.maxValuesCount = 0;
    return desc;
}


unittest
{
    auto uda = NamedArgument.Counter();
    assert(is(typeof(uda) : ArgumentUDA!TYPE, TYPE));
    assert(is(TYPE));
    assert(!is(TYPE == void));
    assert(uda.info.minValuesCount == 0);
    assert(uda.info.maxValuesCount == 0);
}
