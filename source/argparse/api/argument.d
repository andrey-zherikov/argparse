module argparse.api.argument;

import argparse.param;
import argparse.result;

import argparse.internal.arguments: ArgumentInfo;
import argparse.internal.argumentuda: ArgumentUDA, createArgumentUDA;
import argparse.internal.valueparser: ValueParser;
import argparse.internal.actionfunc;
import argparse.internal.novalueactionfunc;
import argparse.internal.parsefunc;
import argparse.internal.validationfunc;
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

auto ref Hidden(T)(auto ref ArgumentUDA!T uda, bool hide = true)
{
    uda.info.hidden = hide;
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
    ArgumentUDA!(ValueParser!(void, void)) arg;
    assert(!arg.info.hidden);
    assert(!arg.info.required);
    assert(arg.info.minValuesCount.isNull);
    assert(arg.info.maxValuesCount.isNull);

    arg = arg.Description("desc").Placeholder("text");
    assert(arg.info.description.get == "desc");
    assert(arg.info.placeholder == "text");

    arg = arg.Description(() => "qwer").Placeholder("text");
    assert(arg.info.description.get == "qwer");

    arg = arg.Hidden.Required.NumberOfValues(10);
    assert(arg.info.hidden);
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
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

auto PositionalArgument(uint position)
{
    auto arg = ArgumentUDA!(ValueParser!(void, void))(ArgumentInfo.init).Required();
    arg.info.position = position;
    return arg;
}

auto PositionalArgument(uint position, string placeholder)
{
    return PositionalArgument(position).Placeholder(placeholder);
}

auto NamedArgument(string[] names...)
{
    return ArgumentUDA!(ValueParser!(void, void))(ArgumentInfo(names.dup)).Optional();
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

auto AllowNoValue(VALUE, T)(ArgumentUDA!T uda, VALUE valueToUse)
{
    return ActionNoValueImpl(uda,SetValue(valueToUse));
}

auto ForceNoValue(VALUE, T)(ArgumentUDA!T uda, VALUE valueToUse)
{
    auto desc = AllowNoValue(uda, valueToUse);
    desc.info.minValuesCount = 0;
    desc.info.maxValuesCount = 0;
    return desc;
}

unittest
{
    auto uda = NamedArgument.AllowNoValue("value");
    assert(is(typeof(uda) : ArgumentUDA!(ValueParser!(void, string))));
    assert(uda.info.minValuesCount == 0);
}

unittest
{
    auto uda = NamedArgument.ForceNoValue("value");
    assert(is(typeof(uda) : ArgumentUDA!(ValueParser!(void, string))));
    assert(uda.info.minValuesCount == 0);
    assert(uda.info.maxValuesCount == 0);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/// Parsing customization

auto PreValidation(T, RETURN, VALUE)(ArgumentUDA!T uda, RETURN function(VALUE value) func)
if((is(VALUE == string) || is(VALUE == string[]) || is(VALUE == RawParam)) &&
    (is(RETURN == bool) || is(RETURN == Result)))
{
    auto desc = createArgumentUDA(uda.info, uda.valueParser.changePreValidation(ValidationFunc!string(func)));

    return desc;
}

///////////////////////////

private auto ParseImpl(T, RECEIVER)(ArgumentUDA!T uda, ParseFunc!RECEIVER func)
{
    auto desc = createArgumentUDA(uda.info, uda.valueParser.changeParse(func));

    static if(is(RECEIVER == string))
        desc.info.minValuesCount = desc.info.maxValuesCount = 1;
    else
    {
        desc.info.minValuesCount = 0;
        desc.info.maxValuesCount = size_t.max;
    }

    return desc;
}

auto Parse(T, RECEIVER, VALUE)(ArgumentUDA!T uda, RECEIVER function(VALUE value) func)
if((is(VALUE == string) || is(VALUE == string[]) || is(VALUE == RawParam)))
{
    return ParseImpl(uda, ParseFunc!RECEIVER(func));
}

auto Parse(T, RETURN, RECEIVER)(ArgumentUDA!T uda, RETURN function(ref RECEIVER receiver, RawParam param) func)
if(is(RETURN == void) || is(RETURN == bool) || is(RETURN == Result))
{
    return ParseImpl(uda, ParseFunc!RECEIVER(func));
}

///////////////////////////

auto Validation(T, RETURN, VALUE)(ArgumentUDA!T uda, RETURN function(VALUE value) func)
if(is(RETURN == bool) || is(RETURN == Result))
{
    static if(!is(VALUE == Param!TYPE, TYPE))
        alias TYPE = VALUE;

    auto desc = createArgumentUDA(uda.info, uda.valueParser.changeValidation(ValidationFunc!TYPE(func)));

    return desc;
}

///////////////////////////

auto Action(T, RETURN, RECEIVER, VALUE)(ArgumentUDA!T uda, RETURN function(ref RECEIVER receiver, VALUE value) func)
if(is(RETURN == void) || is(RETURN == bool) || is(RETURN == Result))
{
    static if(!is(VALUE == Param!TYPE, TYPE))
        alias TYPE = VALUE;

    auto desc = createArgumentUDA(uda.info, uda.valueParser.changeAction(ActionFunc!(RECEIVER, TYPE)(func)));

    return desc;
}

///////////////////////////
private auto ActionNoValueImpl(T, RECEIVER)(ArgumentUDA!T uda, NoValueActionFunc!RECEIVER func)
{
    auto desc = createArgumentUDA(uda.info, uda.valueParser.changeNoValueAction(func));
    desc.info.minValuesCount = 0;
    return desc;
}

package auto ActionNoValue(T, RECEIVER)(ArgumentUDA!T uda, Result function(ref RECEIVER receiver, Param!void param) func)
{
    return ActionNoValueImpl(uda, NoValueActionFunc!RECEIVER(func));
}

///////////////////////////

unittest
{
    auto uda = NamedArgument.PreValidation((RawParam _) => true);
    assert(is(typeof(uda) : ArgumentUDA!(ValueParser!(void, void))));
}

unittest
{
    auto uda = NamedArgument.Parse((string _) => _);
    assert(is(typeof(uda) : ArgumentUDA!(ValueParser!(P, void)), alias P));
    assert(uda.info.minValuesCount == 1);
    assert(uda.info.maxValuesCount == 1);
}

unittest
{
    auto uda = NamedArgument.Parse((string[] _) => _);
    assert(is(typeof(uda) : ArgumentUDA!(ValueParser!(P, void)), alias P));
    assert(uda.info.minValuesCount == 0);
    assert(uda.info.maxValuesCount == size_t.max);
}

unittest
{
    auto uda = NamedArgument.Validation((RawParam _) => true);
    assert(is(typeof(uda) : ArgumentUDA!(ValueParser!(P, void)), alias P));
}

unittest
{
    auto uda = NamedArgument.Action((ref string _1, RawParam _2) {});
    assert(is(typeof(uda) : ArgumentUDA!(ValueParser!(P, R)), alias P, alias R));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


auto AllowedValues(alias values, T)(ArgumentUDA!T uda)
{
    auto desc = uda.Validation((Param!(typeof(values[0])) _) => ValueInList(values)(_));
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
    static Result parseParameter(T)(ref T receiver, RawParam param)
    {
        assert(param.value.length == 0);

        ++receiver;

        return Result.Success;
    }
}

auto Counter(T)(ArgumentUDA!T uda)
{
    auto desc = ArgumentUDA!CounterParsingFunction(uda.info);
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
