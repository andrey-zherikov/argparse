module argparse.internal.argumentudahelpers;

import argparse.api.argument: NamedArgument;
import argparse.config;
import argparse.internal.argumentuda: ArgumentUDA;

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
    import std.traits: getUDAs;

    alias member = __traits(getMember, TYPE, symbol);
    alias MemberType = typeof(member);

    alias udas = getUDAs!(member, ArgumentUDA);
    alias typeUDAs = getUDAs!(MemberType, ArgumentUDA);

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
    enum defaultUDA = ArgumentUDA!void.init;

    auto createUDA(ulong min, ulong max)
    {
        auto uda = defaultUDA;
        uda.info.minValuesCount = min;
        uda.info.maxValuesCount = max;
        return uda;
    }

    @createUDA(5, 10)
    struct FiveToTen {}

    @defaultUDA
    struct UnspecifiedA {}

    struct UnspecifiedB {}

    @createUDA(5, 10) @createUDA(5, 10)
    struct Multiple {}

    struct Args
    {
        @defaultUDA bool flag;
        @defaultUDA int count;
        @defaultUDA @defaultUDA int incorrect;

        @defaultUDA FiveToTen fiveTen;
        @defaultUDA UnspecifiedA ua;
        @defaultUDA UnspecifiedB ub;
        @defaultUDA Multiple mult;

        @createUDA(1, 2) FiveToTen fiveTen1;
        @createUDA(1, 2) UnspecifiedA ua1;
        @createUDA(1, 2) UnspecifiedB ub1;
        @createUDA(1, 2) Multiple mult1;
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
