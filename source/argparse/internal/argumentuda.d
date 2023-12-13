module argparse.internal.argumentuda;

import argparse.internal.arguments: ArgumentInfo;

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
