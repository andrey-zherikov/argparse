module argparse.internal.argumentuda;

import argparse.config;
import argparse.internal.arguments: ArgumentInfo;
import argparse.internal.utils: formatAllowedValues;
import argparse.internal.enumhelpers: getEnumValues;

import std.traits;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) struct ArgumentUDA(ValueParser)
{
    ArgumentInfo info;

    alias parsingFunc = ValueParser;

    auto addDefaults(T)(ArgumentUDA!T uda)
    {
        auto newInfo = info;

        if(newInfo.shortNames.length == 0) newInfo.shortNames = uda.info.shortNames;
        if(newInfo.longNames.length == 0) newInfo.longNames = uda.info.longNames;
        if(newInfo.placeholder.length == 0) newInfo.placeholder = uda.info.placeholder;
        if(!newInfo.description.isSet()) newInfo.description = uda.info.description;
        if(newInfo.position.isNull()) newInfo.position = uda.info.position;
        if(newInfo.minValuesCount.isNull()) newInfo.minValuesCount = uda.info.minValuesCount;
        if(newInfo.maxValuesCount.isNull()) newInfo.maxValuesCount = uda.info.maxValuesCount;

        static if(is(ValueParser == void))
            return ArgumentUDA!ValueParser(newInfo);
        else
            return ArgumentUDA!(ValueParser.addDefaults!T)(newInfo);
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private template defaultValuesCount(TYPE)
if(!is(TYPE == void))
{
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

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package ArgumentUDA getArgumentUDA(MEMBERTYPE, ArgumentUDA)(const Config config, string symbol, ArgumentUDA uda)
{
    import std.algorithm: each, map;
    import std.array: array;
    import std.conv: text;
    import std.range: chain;

    static if(!isBoolean!MEMBERTYPE)
        uda.info.allowBooleanNegation = false;

    if(uda.info.shortNames.length == 0 && uda.info.longNames.length == 0)
    {
        if(symbol.length == 1)
            uda.info.shortNames = [ symbol ];
        else
            uda.info.longNames = [ symbol ];
    }

    if(uda.info.placeholder.length == 0)
    {
        static if(is(MEMBERTYPE == enum))
            uda.info.placeholder = formatAllowedValues(getEnumValues!MEMBERTYPE);
        else if(uda.info.positional)
            uda.info.placeholder = symbol;
        else
        {
            import std.uni : toUpper;
            uda.info.placeholder = symbol.toUpper;
        }
    }

    uda.info.memberSymbol = symbol;

    if(uda.info.positional)
        uda.info.displayNames = [ uda.info.placeholder ];
    else
    {
        alias toDisplayName = _ => ( _.length == 1 ? text(config.namedArgPrefix, _) : text(config.namedArgPrefix, config.namedArgPrefix, _));

        uda.info.displayNames = chain(uda.info.shortNames, uda.info.longNames).map!toDisplayName.array;
    }

    if(!config.caseSensitive)
    {
        uda.info.shortNames.each!((ref _) => _ = config.convertCase(_));
        uda.info.longNames .each!((ref _) => _ = config.convertCase(_));
    }

    // Note: `uda.info.{minValuesCount,maxValuesCount}` are left unchanged

    return uda;
}

unittest
{
    auto createUDA(string placeholder = "")
    {
        ArgumentInfo info;
        info.allowBooleanNegation = true;
        info.position = 0;
        info.placeholder = placeholder;
        return ArgumentUDA!void(info);
    }

    auto res = getArgumentUDA!int(Config.init, "default_name", createUDA()).info;
    assert(!res.allowBooleanNegation);
    assert(res.shortNames == []);
    assert(res.longNames == ["default_name"]);
    assert(res.displayNames == ["default_name"]);
    assert(res.placeholder == "default_name");

    res = getArgumentUDA!int(Config.init, "i", createUDA()).info;
    assert(!res.allowBooleanNegation);
    assert(res.shortNames == ["i"]);
    assert(res.longNames == []);
    assert(res.displayNames == ["i"]);
    assert(res.placeholder == "i");

    res = getArgumentUDA!int(Config.init, "default_name", createUDA("myvalue")).info;
    assert(res.placeholder == "myvalue");
    assert(res.displayNames == ["myvalue"]);
}

unittest
{
    auto createUDA(string placeholder = "")
    {
        ArgumentInfo info;
        info.allowBooleanNegation = true;
        info.placeholder = placeholder;
        return ArgumentUDA!void(info);
    }

    auto res = getArgumentUDA!bool(Config.init, "default_name", createUDA()).info;
    assert(res.allowBooleanNegation);
    assert(res.shortNames == []);
    assert(res.longNames == ["default_name"]);
    assert(res.displayNames == ["--default_name"]);
    assert(res.placeholder == "DEFAULT_NAME");

    res = getArgumentUDA!bool(Config.init, "b", createUDA()).info;
    assert(res.allowBooleanNegation);
    assert(res.shortNames == ["b"]);
    assert(res.longNames == []);
    assert(res.displayNames == ["-b"]);
    assert(res.placeholder == "B");

    res = getArgumentUDA!bool(Config.init, "default_name", createUDA("myvalue")).info;
    assert(res.placeholder == "myvalue");
    assert(res.displayNames == ["--default_name"]);
}

unittest
{
    enum config = {
        Config config;
        config.caseSensitive = false;
        return config;
    }();

    auto createUDA(string placeholder = "")
    {
        ArgumentInfo info;
        info.allowBooleanNegation = true;
        info.placeholder = placeholder;
        return ArgumentUDA!void(info);
    }

    auto res = getArgumentUDA!bool(config, "default_name", createUDA()).info;
    assert(res.allowBooleanNegation);
    assert(res.shortNames == []);
    assert(res.longNames == ["DEFAULT_NAME"]);
    assert(res.displayNames == ["--default_name"]);
    assert(res.placeholder == "DEFAULT_NAME");

    res = getArgumentUDA!bool(config, "b", createUDA()).info;
    assert(res.allowBooleanNegation);
    assert(res.shortNames == ["B"]);
    assert(res.longNames == []);
    assert(res.displayNames == ["-b"]);
    assert(res.placeholder == "B");

    res = getArgumentUDA!bool(config, "default_name", createUDA("myvalue")).info;
    assert(res.placeholder == "myvalue");
    assert(res.displayNames == ["--default_name"]);
}

unittest
{
    enum E { a=1, b=1, c }

    auto createUDA(string placeholder = "")
    {
        ArgumentInfo info;
        info.placeholder = placeholder;
        return ArgumentUDA!void(info);
    }

    auto res = getArgumentUDA!E(Config.init, "default_name", createUDA()).info;
    assert(res.placeholder == "{a,b,c}");

    res = getArgumentUDA!E(Config.init, "default_name", createUDA("myvalue")).info;
    assert(res.placeholder == "myvalue");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package auto getMemberArgumentUDA(TYPE, string symbol, T)(const Config config, ArgumentUDA!T defaultUDA)
{
    alias member = __traits(getMember, TYPE, symbol);
    alias MemberType = typeof(member);

    alias udas = getUDAs!(member, ArgumentUDA);
    alias typeUDAs = getUDAs!(MemberType, ArgumentUDA);

    static assert(udas.length <= 1, "Member "~TYPE.stringof~"."~symbol~" has multiple '*Argument' UDAs");
    static assert(typeUDAs.length <= 1, "Type "~MemberType.stringof~" has multiple '*Argument' UDAs");

    static if(udas.length > 0)
    {
        enum uda0 = udas[0];
        enum checkMinMax0 = uda0.info.minValuesCount.isNull || uda0.info.maxValuesCount.isNull;
    }
    else
    {
        alias uda0 = defaultUDA;
        enum checkMinMax0 = true; // Passed `defaultUDA` always has undefined `minValuesCount`/`maxValuesCount`
    }

    static if(typeUDAs.length > 0)
    {
        auto uda1 = uda0.addDefaults(typeUDAs);
        enum checkMinMax1 = typeUDAs[0].info.minValuesCount.isNull || typeUDAs[0].info.maxValuesCount.isNull;
    }
    else
    {
        alias uda1 = uda0;
        enum checkMinMax1 = true;
    }

    auto newUDA = getArgumentUDA!MemberType(config, symbol, uda1);

    static if(checkMinMax0 && checkMinMax1)
    {
        // We must guard `defaultValuesCount!MemberType` by a `static if` to not instantiate it unless we need it
        // because it produces a compilation error for unsupported types.
        if(newUDA.info.minValuesCount.isNull) newUDA.info.minValuesCount = defaultValuesCount!MemberType.min;
        if(newUDA.info.maxValuesCount.isNull) newUDA.info.maxValuesCount = defaultValuesCount!MemberType.max;
    }

    return newUDA;
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
        return getMemberArgumentUDA!(Args, symbol)(Config.init, defaultUDA).info;
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
