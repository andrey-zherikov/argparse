module argparse.internal.argumentudahelpers;

import argparse.api.argument: NamedArgument;
import argparse.config;
import argparse.internal.argumentuda: ArgumentUDA;

// `@NamedArgument` attaches the function itself as a UDA, but we should treat it the same as `@NamedArgument()`.
package enum isArgumentUDA(alias _ : NamedArgument) = true;
package enum isArgumentUDA(alias uda) = is(typeof(uda) == ArgumentUDA!T, T);

private template defaultValuesCount(TYPE)
if(!is(TYPE == void))
{
    import std.traits;

    static if(is(typeof(*TYPE) == function) || is(typeof(*TYPE) == delegate))
        alias T = typeof(*TYPE);
    else
        alias T = TYPE;

    static if(isBoolean!T)
    {
        enum min = 0;
        enum max = 0;
    }
    else static if(isSomeString!T || isScalarType!T)
    {
        enum min = 1;
        enum max = 1;
    }
    else static if(isStaticArray!T)
    {
        enum min = T.length;
        enum max = T.length;
    }
    else static if(isArray!T || isAssociativeArray!T)
    {
        enum min = 1;
        enum max = ulong.max;
    }
    else static if(is(T == function))
    {
        // ... function()
        static if(__traits(compiles, { T(); }))
        {
            enum min = 0;
            enum max = 0;
        }
            // ... function(string value)
        else static if(__traits(compiles, { T(string.init); }))
        {
            enum min = 1;
            enum max = 1;
        }
            // ... function(string[] value)
        else static if(__traits(compiles, { T([string.init]); }))
        {
            enum min = 0;
            enum max = ulong.max;
        }
            // ... function(RawParam param)
        else static if(__traits(compiles, { T(RawParam.init); }))
        {
            enum min = 1;
            enum max = ulong.max;
        }
        else
            static assert(false, "Unsupported callback: " ~ T.stringof);
    }
    else
        static assert(false, "Type is not supported: " ~ T.stringof);
}

package auto getMemberArgumentUDA(TYPE, string symbol)(const Config config)
{
    import argparse.internal.arguments: finalize;
    import std.meta: Filter;

    alias member = __traits(getMember, TYPE, symbol);
    alias MemberType = typeof(member);

    alias udas     = Filter!(isArgumentUDA, __traits(getAttributes, member));
    alias typeUDAs = Filter!(isArgumentUDA, __traits(getAttributes, MemberType));

    static assert(udas.length <= 1, "Member "~TYPE.stringof~"."~symbol~" has multiple '*Argument' UDAs");
    static assert(typeUDAs.length <= 1, "Type "~MemberType.stringof~" has multiple '*Argument' UDAs");

    static if(udas.length > 0)
        enum memberUDA = udas[0];
    else
        enum memberUDA = NamedArgument();

    static if(typeUDAs.length > 0)
        enum initUDA = memberUDA.addDefaults(typeUDAs[0]);
    else
        enum initUDA = memberUDA;

    auto result = initUDA;
    result.info = result.info.finalize!MemberType(config, symbol);

    static if(initUDA.info.minValuesCount.isNull) result.info.minValuesCount = defaultValuesCount!MemberType.min;
    static if(initUDA.info.maxValuesCount.isNull) result.info.maxValuesCount = defaultValuesCount!MemberType.max;

    return result;
}

unittest
{
    import argparse.api.argument: NumberOfValues;

    @(NamedArgument.NumberOfValues(5, 10))
    struct FiveToTen {}

    @NamedArgument
    struct UnspecifiedA {}

    struct UnspecifiedB {}

    @(NamedArgument.NumberOfValues(5, 10))
    @(NamedArgument.NumberOfValues(5, 10))
    struct Multiple {}

    struct Args
    {
        @NamedArgument bool flag;
        @NamedArgument int count;
        @NamedArgument @NamedArgument() int incorrect;

        @NamedArgument FiveToTen fiveTen;
        @NamedArgument UnspecifiedA ua;
        @NamedArgument UnspecifiedB ub;
        @NamedArgument Multiple mult;

        @(NamedArgument.NumberOfValues(1, 2)) FiveToTen fiveTen1;
        @(NamedArgument.NumberOfValues(1, 2)) UnspecifiedA ua1;
        @(NamedArgument.NumberOfValues(1, 2)) UnspecifiedB ub1;
        @(NamedArgument.NumberOfValues(1, 2)) Multiple mult1;
    }

    auto getInfo(string symbol)()
    {
        return getMemberArgumentUDA!(Args, symbol)(Config.init).info;
    }

    // Built-in types:

    auto res = getInfo!"flag";
    assert(res.minValuesCount == 0);
    assert(res.maxValuesCount == 0);

    res = getInfo!"count";
    assert(res.minValuesCount == 1);
    assert(res.maxValuesCount == 1);

    assert(!__traits(compiles, getInfo!"incorrect"));

    // With type-inherited quantifiers:

    res = getInfo!"fiveTen";
    assert(res.minValuesCount == 5);
    assert(res.maxValuesCount == 10);

    assert(!__traits(compiles, getInfo!"ua"));
    assert(!__traits(compiles, getInfo!"ub"));
    assert(!__traits(compiles, getInfo!"mult"));

    // With explicit quantifiers:

    res = getInfo!"fiveTen1";
    assert(res.minValuesCount == 1);
    assert(res.maxValuesCount == 2);

    res = getInfo!"ua1";
    assert(res.minValuesCount == 1);
    assert(res.maxValuesCount == 2);

    res = getInfo!"ub1";
    assert(res.minValuesCount == 1);
    assert(res.maxValuesCount == 2);

    assert(!__traits(compiles, getInfo!"mult1"));
}
