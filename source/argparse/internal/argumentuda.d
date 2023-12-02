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

private ArgumentUDA getArgumentUDAImpl0(MEMBERTYPE, ArgumentUDA)(ref const Config config, string symbol, ArgumentUDA uda)
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

    // `uda.info.{minValuesCount,maxValuesCount}` are set in the function below.

    return uda;
}

private ArgumentUDA getArgumentUDAImpl(MEMBERTYPE, bool checkMinMax, ArgumentUDA)(const Config config, string symbol, ArgumentUDA uda)
{
    auto newUDA = getArgumentUDAImpl0!MEMBERTYPE(config, symbol, uda);
    static if(checkMinMax) // We test it here so that `Impl0` does not have `checkMinMax` in its template parameters.
    {
        // We must guard `defaultValuesCount!MEMBERTYPE` by a `static if` to not instantiate it unless we need it
        // because it produces a compilation error for unsupported types. Since we cannot examine `newUDA` (nor `uda`)
        // in a `static if`, we have to be communicated by some other means if its `minValuesCount` and/or
        // `maxValuesCount` can be null. That's why `checkMinMax` is necessary.
        if(newUDA.info.minValuesCount.isNull) newUDA.info.minValuesCount = defaultValuesCount!MEMBERTYPE.min;
        if(newUDA.info.maxValuesCount.isNull) newUDA.info.maxValuesCount = defaultValuesCount!MEMBERTYPE.max;
    }
    return newUDA;
}

package auto getArgumentUDA(MEMBERTYPE, bool checkMinMax, SomeArgumentUDA)(const Config config, string symbol, SomeArgumentUDA initUDA)
{
    alias typeUDAs = getUDAs!(MEMBERTYPE, ArgumentUDA);
    static if(typeUDAs.length == 1)
    {
        enum checkMinMax = checkMinMax && (typeUDAs[0].info.minValuesCount.isNull || typeUDAs[0].info.maxValuesCount.isNull);
        auto uda = initUDA.addDefaults(typeUDAs);
    }
    else
        alias uda = initUDA;
    return getArgumentUDAImpl!(MEMBERTYPE, checkMinMax)(config, symbol, uda);
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
    assert(createUDA().info.allowBooleanNegation); // make codecov happy

    auto res = getArgumentUDA!(int, true)(Config.init, "default_name", createUDA()).info;
    assert(res == getArgumentUDAImpl!(int, true)(Config.init, "default_name", createUDA()).info);
    assert(!res.allowBooleanNegation);
    assert(res.shortNames == []);
    assert(res.longNames == ["default_name"]);
    assert(res.displayNames == ["default_name"]);
    assert(res.minValuesCount == defaultValuesCount!int.min);
    assert(res.maxValuesCount == defaultValuesCount!int.max);
    assert(res.placeholder == "default_name");

    res = getArgumentUDA!(int, true)(Config.init, "i", createUDA()).info;
    assert(res == getArgumentUDAImpl!(int, true)(Config.init, "i", createUDA()).info);
    assert(!res.allowBooleanNegation);
    assert(res.shortNames == ["i"]);
    assert(res.longNames == []);
    assert(res.displayNames == ["i"]);
    assert(res.minValuesCount == defaultValuesCount!int.min);
    assert(res.maxValuesCount == defaultValuesCount!int.max);
    assert(res.placeholder == "i");

    res = getArgumentUDA!(int, true)(Config.init, "default_name", createUDA("myvalue")).info;
    assert(res == getArgumentUDAImpl!(int, true)(Config.init, "default_name", createUDA("myvalue")).info);
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
    assert(createUDA().info.allowBooleanNegation); // make codecov happy

    auto res = getArgumentUDA!(bool, true)(Config.init, "default_name", createUDA()).info;
    assert(res == getArgumentUDAImpl!(bool, true)(Config.init, "default_name", createUDA()).info);
    assert(res.allowBooleanNegation);
    assert(res.shortNames == []);
    assert(res.longNames == ["default_name"]);
    assert(res.displayNames == ["--default_name"]);
    assert(res.minValuesCount == defaultValuesCount!bool.min);
    assert(res.maxValuesCount == defaultValuesCount!bool.max);
    assert(res.placeholder == "DEFAULT_NAME");

    res = getArgumentUDA!(bool, true)(Config.init, "b", createUDA()).info;
    assert(res == getArgumentUDAImpl!(bool, true)(Config.init, "b", createUDA()).info);
    assert(res.allowBooleanNegation);
    assert(res.shortNames == ["b"]);
    assert(res.longNames == []);
    assert(res.displayNames == ["-b"]);
    assert(res.minValuesCount == defaultValuesCount!bool.min);
    assert(res.maxValuesCount == defaultValuesCount!bool.max);
    assert(res.placeholder == "B");

    res = getArgumentUDA!(bool, true)(Config.init, "default_name", createUDA("myvalue")).info;
    assert(res == getArgumentUDAImpl!(bool, true)(Config.init, "default_name", createUDA("myvalue")).info);
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
    assert(createUDA().info.allowBooleanNegation); // make codecov happy

    auto res = getArgumentUDA!(bool, true)(config, "default_name", createUDA()).info;
    assert(res == getArgumentUDAImpl!(bool, true)(config, "default_name", createUDA()).info);
    assert(res.allowBooleanNegation);
    assert(res.shortNames == []);
    assert(res.longNames == ["DEFAULT_NAME"]);
    assert(res.displayNames == ["--default_name"]);
    assert(res.minValuesCount == defaultValuesCount!bool.min);
    assert(res.maxValuesCount == defaultValuesCount!bool.max);
    assert(res.placeholder == "DEFAULT_NAME");

    res = getArgumentUDA!(bool, true)(config, "b", createUDA()).info;
    assert(res == getArgumentUDAImpl!(bool, true)(config, "b", createUDA()).info);
    assert(res.allowBooleanNegation);
    assert(res.shortNames == ["B"]);
    assert(res.longNames == []);
    assert(res.displayNames == ["-b"]);
    assert(res.minValuesCount == defaultValuesCount!bool.min);
    assert(res.maxValuesCount == defaultValuesCount!bool.max);
    assert(res.placeholder == "B");

    res = getArgumentUDA!(bool, true)(config, "default_name", createUDA("myvalue")).info;
    assert(res == getArgumentUDAImpl!(bool, true)(config, "default_name", createUDA("myvalue")).info);
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
    assert(createUDA().info.allowBooleanNegation); // make codecov happy

    auto res = getArgumentUDA!(E, true)(Config.init, "default_name", createUDA()).info;
    assert(res == getArgumentUDAImpl!(E, true)(Config.init, "default_name", createUDA()).info);
    assert(res.placeholder == "{a,b,c}");

    res = getArgumentUDA!(E, true)(Config.init, "default_name", createUDA("myvalue")).info;
    assert(res == getArgumentUDAImpl!(E, true)(Config.init, "default_name", createUDA("myvalue")).info);
    assert(res.placeholder == "myvalue");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package auto getMemberArgumentUDA(TYPE, string symbol, T)(const Config config, ArgumentUDA!T defaultUDA)
{
    alias member = __traits(getMember, TYPE, symbol);

    alias udas = getUDAs!(member, ArgumentUDA);
    static assert(udas.length <= 1, "Member "~TYPE.stringof~"."~symbol~" has multiple '*Argument' UDAs");

    static if(udas.length > 0)
    {
        enum uda = udas[0];
        enum checkMinMax = uda.info.minValuesCount.isNull || uda.info.maxValuesCount.isNull;
    }
    else
    {
        alias uda = defaultUDA;
        enum checkMinMax = true;
    }

    return getArgumentUDA!(typeof(member), checkMinMax)(config, symbol, uda);
}

