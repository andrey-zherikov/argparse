module argparse.internal.argumentuda;

import argparse.internal.arguments: ArgumentInfo;
import argparse.internal.utils: formatAllowedValues, EnumMembersAsStrings;

import std.traits;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) struct ArgumentUDA(ValueParseFunctions)
{
    ArgumentInfo info;

    alias parsingFunc = ValueParseFunctions;

    auto addDefaults(T)(ArgumentUDA!T uda)
    {
        auto newInfo = info;

        if(newInfo.names.length == 0) newInfo.names = uda.info.names;
        if(newInfo.placeholder.length == 0) newInfo.placeholder = uda.info.placeholder;
        if(!newInfo.description.isSet()) newInfo.description = uda.info.description;
        if(newInfo.position.isNull()) newInfo.position = uda.info.position;
        if(newInfo.minValuesCount.isNull()) newInfo.minValuesCount = uda.info.minValuesCount;
        if(newInfo.maxValuesCount.isNull()) newInfo.maxValuesCount = uda.info.maxValuesCount;

        return ArgumentUDA!(parsingFunc.addDefaults!(uda.parsingFunc))(newInfo);
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
        enum min = 1;
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

//private enum setupInfo(ArgumentInfo origInfo, TYPE, alias symbol) = {
//    import std.traits: isBoolean;
//
//    auto info = origInfo;
//
//    static if(!isBoolean!TYPE)
//        info.allowBooleanNegation = false;
//
//    static if(origInfo.names.length == 0)
//        info.names = [ symbol ];
//
//    static if(origInfo.placeholder.length == 0)
//    {
//        static if(is(TYPE == enum))
//            info.placeholder = formatAllowedValues!(EnumMembersAsStrings!TYPE);
//        else static if(origInfo.positional)
//            info.placeholder = symbol;
//        else
//        {
//            import std.uni : toUpper;
//            info.placeholder = symbol.toUpper;
//        }
//    }
//
//    static if(is(typeof(*TYPE) == function) || is(typeof(*TYPE) == delegate))
//        alias countType = typeof(*TYPE);
//    else
//        alias countType = TYPE;
//
//    static if(origInfo.minValuesCount.isNull) info.minValuesCount = defaultValuesCount!countType.min;
//    static if(origInfo.maxValuesCount.isNull) info.maxValuesCount = defaultValuesCount!countType.max;
//
//    return info;
//}();
//
//unittest
//{
//    auto createInfo(string placeholder = "")()
//    {
//        ArgumentInfo info;
//        info.allowBooleanNegation = true;
//        info.position = 0;
//        info.placeholder = placeholder;
//        return info;
//    }
//    assert(createInfo().allowBooleanNegation); // make codecov happy
//
//    auto res = setupInfo!(createInfo(), int, "default-name");
//    assert(!res.allowBooleanNegation);
//    assert(res.names == [ "default-name" ]);
//    assert(res.minValuesCount == defaultValuesCount!int.min);
//    assert(res.maxValuesCount == defaultValuesCount!int.max);
//    assert(res.placeholder == "default-name");
//
//    res = setupInfo!(createInfo!"myvalue", int, "default-name");
//    assert(res.placeholder == "myvalue");
//}
//
//unittest
//{
//    auto createInfo(string placeholder = "")()
//    {
//        ArgumentInfo info;
//        info.allowBooleanNegation = true;
//        info.placeholder = placeholder;
//        return info;
//    }
//    assert(createInfo().allowBooleanNegation); // make codecov happy
//
//    auto res = setupInfo!(createInfo(), bool, "default_name");
//    assert(res.allowBooleanNegation);
//    assert(res.names == ["default_name"]);
//    assert(res.minValuesCount == defaultValuesCount!bool.min);
//    assert(res.maxValuesCount == defaultValuesCount!bool.max);
//    assert(res.placeholder == "DEFAULT_NAME");
//
//    res = setupInfo!(createInfo!"myvalue", bool, "default_name");
//    assert(res.placeholder == "myvalue");
//}
//
//unittest
//{
//    enum E { a=1, b=1, c }
//
//    auto createInfo(string placeholder = "")()
//    {
//        ArgumentInfo info;
//        info.placeholder = placeholder;
//        return info;
//    }
//    assert(createInfo().allowBooleanNegation); // make codecov happy
//
//    auto res = setupInfo!(createInfo(), E, "default-name");
//    assert(res.placeholder == "{a,b,c}");
//
//    res = setupInfo!(createInfo!"myvalue", E, "default-name");
//    assert(res.placeholder == "myvalue");
//}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package enum getArgumentUDA(alias config, TYPE, alias symbol, alias defaultUDA) = {
    alias member = __traits(getMember, TYPE, symbol);
    alias MEMBERTYPE = typeof(member);

    enum udas = getUDAs!(member, ArgumentUDA);
    static assert(udas.length <= 1, "Member "~TYPE.stringof~"."~symbol~" has multiple '*Argument' UDAs");

    static if(udas.length > 0)
        alias uda1 = udas[0];
    else
        enum uda1 = defaultUDA();

    static if(__traits(compiles, getUDAs!(MEMBERTYPE, ArgumentUDA)) && getUDAs!(MEMBERTYPE, ArgumentUDA).length == 1)
        enum uda2 = uda1.addDefaults(getUDAs!(MEMBERTYPE, ArgumentUDA)[0]);
    else
        alias uda2 = uda1;

    auto uda = uda2;

    // DMD 2.100.2 crashes if below code is moved to a separate function
    static if(!isBoolean!MEMBERTYPE)
        uda.info.allowBooleanNegation = false;

    static if(uda2.info.names.length == 0)
        uda.info.names = [ symbol ];

    static if(uda2.info.placeholder.length == 0)
    {
        static if(is(MEMBERTYPE == enum))
            uda.info.placeholder = formatAllowedValues!(EnumMembersAsStrings!MEMBERTYPE);
        else static if(uda2.info.positional)
            uda.info.placeholder = symbol;
        else
        {
            import std.uni : toUpper;
            uda.info.placeholder = symbol.toUpper;
        }
    }

    static if(uda2.info.minValuesCount.isNull) uda.info.minValuesCount = defaultValuesCount!MEMBERTYPE.min;
    static if(uda2.info.maxValuesCount.isNull) uda.info.maxValuesCount = defaultValuesCount!MEMBERTYPE.max;

    return uda;
}();

