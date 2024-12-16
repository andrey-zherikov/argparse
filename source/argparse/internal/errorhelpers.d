module argparse.internal.errorhelpers;

import argparse.config;
import argparse.param;
import argparse.result;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package Result processingError(T)(Param!T param, string prefix = "Can't process value")
{
    import std.conv: to;
    import std.array: appender;

    auto a = appender!string(prefix);

    static if(__traits(hasMember, param, "value"))
    {
        a ~= " '";
        a ~= param.config.styling.positionalArgumentValue(param.value.to!string);
        a ~= "'";
    }

    if(param.name.length > 0 && param.name[0] == param.config.namedArgPrefix)
    {
        a ~= " for argument '";
        a ~= param.config.styling.argumentName(param.name);
        a ~= "'";
    }

    return Result.Error(a[]);
}

package Result invalidValueError(T)(Param!T param)
{
    return processingError(param, "Invalid value");
}


unittest
{
    Config config;
    assert(processingError(Param!void(&config, "")).isError("Can't process value"));
    assert(processingError(Param!void(&config, "--abc")).isError("Can't process value for argument","--abc"));
    assert(processingError(Param!(int[])(&config, "", [1,2])).isError("Can't process value '","[1, 2]"));
    assert(processingError(Param!(int[])(&config, "--abc", [1,2])).isError("Can't process value '","[1, 2]","' for argument '","--abc"));
}
