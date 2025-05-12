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
    assert(min <= max);

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
    assert(arg.info.minValuesCount == 10);
    assert(arg.info.maxValuesCount == 10);

    arg = arg.Optional.NumberOfValues(20,30);
    assert(!arg.info.required);
    assert(arg.info.minValuesCount == 20);
    assert(arg.info.maxValuesCount == 30);

    arg = arg.MinNumberOfValues(2).MaxNumberOfValues(3);
    assert(arg.info.minValuesCount == 2);
    assert(arg.info.maxValuesCount == 3);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private struct NotSet {}

private enum isSet(T : NotSet) = false;
private enum isSet(T) = true;

private enum isNotSet(T : NotSet) = true;
private enum isNotSet(T) = false;

private enum isPreValidation(T) = is(T == RETURN function(VALUE), RETURN, VALUE) &&
    (is(VALUE == string) || is(VALUE == string[]) || is(VALUE == RawParam)) &&
    (is(RETURN == bool) || is(RETURN == Result));

private enum isParse(T) =
    (
        is(T == RECEIVER function(VALUE), RECEIVER, VALUE) &&
        (is(VALUE == string) || is(VALUE == string[]) || is(VALUE == RawParam))
    ) ||
    (
        is(T == RETURN function(ref RECEIVER, RawParam), RETURN, RECEIVER) &&
        (is(RETURN == void) || is(RETURN == bool) || is(RETURN == Result))
    );

private enum isValidation(T) = is(T == RETURN function(VALUE), RETURN, VALUE) &&
    (is(RETURN == bool) || is(RETURN == Result));

private enum isAction(T) = is(T == RETURN function(ref RECEIVER, VALUE), RETURN, RECEIVER, VALUE) &&
    (is(RETURN == void) || is(RETURN == bool) || is(RETURN == Result));

//positional:
//Placeholder

//auto Argument(
//    AllowNoValue = NotSet,
//    ForceNoValue = NotSet,
//    PreValidation = NotSet,
//    Parse = NotSet,
//    Validation = NotSet,
//    Action = NotSet,
//    AllowedValues = NotSet
//)(
//    bool Required,
//    bool Hidden = false,
//    string description = "",
//    size_t minNumberOfValues = size_t(-1),
//    size_t maxNumberOfValues = size_t(-1),
//    AllowNoValue allowNoValue = AllowNoValue.init,
//    ForceNoValue forceNoValue = ForceNoValue.init,
//    PreValidation preValidation = PreValidation.init,
//    Parse parse = Parse.init,
//    Validation validation = Validation.init,
//    Action action = Action.init,
//    AllowedValues allowedValues = AllowedValues.init
//)
//if(
//    (isNotSet!AllowNoValue || isNotSet!ForceNoValue) &&
//    (isNotSet!PreValidation || isPreValidation!PreValidation) &&
//    (isNotSet!Parse || isParse!Parse) &&
//    (isNotSet!Validation || isValidation!Validation) &&
//    (isNotSet!Action || isAction!Action) &&
//    (isNotSet!AllowedValues || isArray!AllowedValues)
//)
//{}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
// THIS IS NOT USABLE DUE TO https://github.com/dlang/dmd/issues/21335
// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
auto PositionalArgument(
        AllowNoValue    = NotSet,
        ForceNoValue    = NotSet,
        AllowedValues   = NotSet,
        PreValidation   = NotSet,
        Parse           = NotSet,
        Validation      = NotSet,
        Action          = NotSet,
    )
    (
        uint position               = uint(-1),
        string placeholder          = "",
        bool required               = true,
        bool hidden                 = false,
        string description          = "",
        size_t minNumberOfValues    = size_t(-1),
        size_t maxNumberOfValues    = size_t(-1),
        AllowNoValue allowNoValue   = AllowNoValue.init,
        ForceNoValue forceNoValue   = ForceNoValue.init,
        AllowedValues allowedValues = AllowedValues.init,
        PreValidation preValidation = PreValidation.init,
        Parse parse                 = Parse.init,
        Validation validation       = Validation.init,
        Action action               = Action.init,
    )
if(
    (!isSet!AllowNoValue  || !isSet!ForceNoValue) &&
    (!isSet!AllowedValues || isArray!AllowedValues) &&
    (!isSet!PreValidation || isPreValidation!PreValidation) &&
    (!isSet!Parse         || isParse!Parse) &&
    (!isSet!Validation    || isValidation!Validation) &&
    (!isSet!Action        || isAction!Action)
)
{
    assert(minNumberOfValues == size_t(-1) || maxNumberOfValues == size_t(-1) || minNumberOfValues <= maxNumberOfValues);

    auto arg0 = ArgumentUDA!(ValueParser!(void, void))(ArgumentInfo.init);
    arg0.info.positional = true;

    if(position != uint(-1))
        arg0.info.position = position;

    if(placeholder.length > 0)
        arg0 = arg0.Placeholder(placeholder);

    if(required)
        arg0 = arg0.Required();
    else
        arg0 = arg0.Optional();

    if(hidden)
        arg0 = arg0.Hidden();

    if(description.length > 0)
        arg0 = arg0.Description(description);

    if(minNumberOfValues != size_t(-1))
        arg0 = arg0.MinNumberOfValues(minNumberOfValues);

    if(maxNumberOfValues != size_t(-1))
        arg0 = arg0.MaxNumberOfValues(maxNumberOfValues);

    static if(isSet!AllowNoValue)
        auto arg1 = arg0.AllowNoValue(allowNoValue);
    else
        auto arg1 = arg0;

    static if(isSet!ForceNoValue)
        auto arg2 = arg1.ForceNoValue(forceNoValue);
    else
        auto arg2 = arg1;

    static if(isSet!AllowedValues)
        auto arg3 = arg2.AllowedValues(allowedValues);
    else
        auto arg3 = arg2;

    static if(isSet!PreValidation)
        auto arg4 = arg3.PreValidation(preValidation);
    else
        auto arg4 = arg3;

    static if(isSet!Parse)
        auto arg5 = arg4.Parse(parse);
    else
        auto arg5 = arg4;

    static if(isSet!Validation)
        auto arg6 = arg5.Validation(validation);
    else
        auto arg6 = arg5;

    static if(isSet!Action)
        auto arg7 = arg6.Action(action);
    else
        auto arg7 = arg6;

    return arg7;
}

unittest
{
    auto arg = PositionalArgument();
    assert(arg.info.required);
    assert(arg.info.positional);
    assert(arg.info.position.isNull);
}

unittest
{
    auto arg = PositionalArgument(
        position          : 3,
        placeholder       : "placeholder",
        required          : false,
        hidden            : true,
        description       : "description",
        minNumberOfValues : 5,
        maxNumberOfValues : 7,
    );
    assert(arg.info.positional);
    assert(arg.info.position == 3);
    assert(arg.info.placeholder == "placeholder");
    assert(!arg.info.required);
    assert(arg.info.hidden);
    assert(arg.info.description.get == "description");
    assert(arg.info.minValuesCount == 5);
    assert(arg.info.maxValuesCount == 7);
}

unittest
{
    assert(PositionalArgument(allowNoValue : "abc") == PositionalArgument().AllowNoValue("abc"));
    assert(PositionalArgument(forceNoValue : "abc") == PositionalArgument().ForceNoValue("abc"));
}


//!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! // TODO: unittest for ^


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

auto PositionalArgument(uint position)
{
    auto arg = ArgumentUDA!(ValueParser!(void, void))(ArgumentInfo.init).Required();
    arg.info.position = position;
    arg.info.positional = true;
    return arg;
}

auto PositionalArgument(uint position, string placeholder)
{
    return PositionalArgument(position).Placeholder(placeholder);
}

auto NamedArgument(string[] shortNames, string[] longNames)
{
    return ArgumentUDA!(ValueParser!(void, void))(ArgumentInfo(shortNames, longNames)).Optional();
}

auto NamedArgument(string[] names...)
{
    auto arg = NamedArgument([], []);
    arg.info.namesToSplit = names;
    return arg;
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
    auto arg = NamedArgument("f","foo");
    assert(!arg.info.required);
    assert(!arg.info.positional);
    assert(arg.info.shortNames == []);
    assert(arg.info.longNames == []);
    assert(arg.info.namesToSplit == ["f","foo"]);
}

unittest
{
    auto arg = NamedArgument(["f","foo"]);
    assert(!arg.info.required);
    assert(!arg.info.positional);
    assert(arg.info.shortNames == []);
    assert(arg.info.longNames == []);
    assert(arg.info.namesToSplit == ["f","foo"]);
}

unittest
{
    auto arg = NamedArgument(["f"],["foo"]);
    assert(!arg.info.required);
    assert(!arg.info.positional);
    assert(arg.info.shortNames == ["f"]);
    assert(arg.info.longNames == ["foo"]);
    assert(arg.info.namesToSplit == []);
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


auto AllowedValues(TYPE, T)(ArgumentUDA!T uda, TYPE[] values...)
{
    auto desc = createArgumentUDA(uda.info, uda.valueParser.changeValidation(ValueInList(values)));
    if(desc.info.placeholder.length == 0)
        desc.info.placeholder = formatAllowedValues(values);

    return desc;
}

unittest
{
    assert(NamedArgument.AllowedValues(1, 3, 5).info.placeholder == "{1,3,5}");
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
