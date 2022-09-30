module argparse.internal.argumentuda;

import argparse.internal.arguments: ArgumentInfo;

import std.traits: getUDAs;

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

package enum getArgumentUDA(alias config, TYPE, alias symbol, alias defaultUDA) = {
    alias member = __traits(getMember, TYPE, symbol);

    enum udas = getUDAs!(member, ArgumentUDA);
    static assert(udas.length <= 1, "Member "~TYPE.stringof~"."~symbol~" has multiple '*Argument' UDAs");

    static if(udas.length > 0)
        alias uda1 = udas[0];
    else
        enum uda1 = defaultUDA();

    static if(__traits(compiles, getUDAs!(typeof(member), ArgumentUDA)) && getUDAs!(typeof(member), ArgumentUDA).length == 1)
        enum uda2 = uda1.addDefaults(getUDAs!(typeof(member), ArgumentUDA)[0]);
    else
        alias uda2 = uda1;

    return uda2;
}();

