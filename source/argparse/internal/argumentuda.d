module argparse.internal.argumentuda;

import argparse.config;
import argparse.param;
import argparse.result;
import argparse.internal.arguments: ArgumentInfo;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) auto createArgumentUDA(ValueParser)(ArgumentInfo info, ValueParser valueParser)
{
    return ArgumentUDA!ValueParser(info, valueParser);
}

package(argparse) struct ArgumentUDA(ValueParser)
{
    package(argparse) ArgumentInfo info;

    package(argparse) ValueParser valueParser;

    package Result parse(COMMAND_STACK, RECEIVER)(const COMMAND_STACK cmdStack, ref RECEIVER receiver, RawParam param)
    {
        static assert(!is(RECEIVER == T*, T));
        try
        {
            auto res = info.checkValuesCount(param);
            if(!res)
                return res;

            return valueParser.parseParameter(receiver, param);
        }
        catch(Exception e)
        {
            return Result.Error("Argument '", param.config.styling.argumentName(param.name), ": ", e.msg);
        }
    }

    package auto addDefaults(T)(ArgumentUDA!T uda)
    {
        auto newInfo = info;

        if(newInfo.shortNames.length == 0) newInfo.shortNames = uda.info.shortNames;
        if(newInfo.longNames.length == 0) newInfo.longNames = uda.info.longNames;
        if(newInfo.placeholder.length == 0) newInfo.placeholder = uda.info.placeholder;
        if(!newInfo.description.isSet()) newInfo.description = uda.info.description;
        if(newInfo.position.isNull()) newInfo.position = uda.info.position;
        if(!newInfo.positional) newInfo.positional = uda.info.positional;
        if(newInfo.minValuesCount.isNull()) newInfo.minValuesCount = uda.info.minValuesCount;
        if(newInfo.maxValuesCount.isNull()) newInfo.maxValuesCount = uda.info.maxValuesCount;

        auto newValueParser = valueParser.addDefaults(uda.valueParser);

        return createArgumentUDA(newInfo, newValueParser);
    }

    auto addReceiverTypeDefaults(T)()
    {
        static assert(!is(T == P*, P));

        static if(__traits(hasMember, valueParser, "typeDefaults"))
        {
            auto newValueParser = valueParser.addDefaults(valueParser.typeDefaults!T);

            return createArgumentUDA(info, newValueParser);
        }
        else
            return this;
    }
}

unittest
{
    struct S(string value)
    {
        string str = value;
        auto addDefaults(T)(T s) {
            static if(value.length == 0)
                return s;
            else
                return this;
        }
    }

    ArgumentUDA!(S!"foo1") arg1;
    arg1.info.shortNames = ["a1","b1"];
    arg1.info.longNames = ["aa1","bb1"];
    arg1.info.placeholder = "ph1";
    arg1.info.description = "des1";
    arg1.info.position = 1;
    arg1.info.positional = true;
    arg1.info.minValuesCount = 2;
    arg1.info.maxValuesCount = 3;

    ArgumentUDA!(S!"foo2") arg2;
    arg2.info.shortNames = ["a2","b2"];
    arg2.info.longNames = ["aa2","bb2"];
    arg2.info.placeholder = "ph2";
    arg2.info.description = "des2";
    arg2.info.position = 10;
    arg1.info.positional = true;
    arg2.info.minValuesCount = 20;
    arg2.info.maxValuesCount = 30;

    {
        // values shouldn't be changed
        auto res = arg1.addDefaults(arg2);
        assert(res.info.shortNames == ["a1", "b1"]);
        assert(res.info.longNames == ["aa1", "bb1"]);
        assert(res.info.placeholder == "ph1");
        assert(res.info.description.get == "des1");
        assert(res.info.position.get == 1);
        assert(res.info.minValuesCount == 2);
        assert(res.info.maxValuesCount == 3);
        assert(res.valueParser.str == "foo1");
    }

    {    // values should be changed
        auto res = ArgumentUDA!(S!"").init.addDefaults(arg1);
        assert(res.info.shortNames == ["a1", "b1"]);
        assert(res.info.longNames == ["aa1", "bb1"]);
        assert(res.info.placeholder == "ph1");
        assert(res.info.description.get == "des1");
        assert(res.info.position.get == 1);
        assert(res.info.minValuesCount == 2);
        assert(res.info.maxValuesCount == 3);
        assert(res.valueParser.str == "foo1");
    }
}
