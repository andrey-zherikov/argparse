module argparse.internal.errorhelpers;

import argparse.config;
import argparse.param;
import argparse.result;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
private auto createErrorMessage(T)(Param!T param, string prefix)
{
    import std.array: appender;
    import std.conv: to;

    auto a = appender!string(prefix);

    static if(__traits(hasMember, param, "value"))
    {
        a ~= " '";
        if(param.isNamedArg)
            a ~= param.config.styling.namedArgumentValue(param.value.to!string);
        else
            a ~= param.config.styling.positionalArgumentValue(param.value.to!string);
        a ~= "'";
    }

    if(param.isNamedArg)
    {
        a ~= " for argument '";
        a ~= param.config.styling.argumentName(param.name);
        a ~= "'";
    }

    return a;
}

package Result processingError(T)(Param!T param)
{
    return Result.Error(createErrorMessage(param, "Can't process value")[]);
}

package Result invalidValueError(T)(Param!T param, string suffix = "")
{
    auto msg = createErrorMessage(param, "Invalid value");
    msg ~= suffix;

    return Result.Error(msg[]);
}


unittest
{
    Config config;
    assert(processingError(Param!void(&config, "--abc")).isError("Can't process value for argument","--abc"));
    assert(processingError(Param!void(&config, "")).isError("Can't process value"));
    assert(processingError(Param!(int[])(&config, "", [1,2])).isError("Can't process value '","[1, 2]"));
    assert(processingError(Param!(int[])(&config, "--abc", [1,2])).isError("Can't process value '","[1, 2]","' for argument '","--abc"));
    assert(invalidValueError(Param!(int[])(&config, "--abc", [1,2])).isError("Invalid value '","[1, 2]","' for argument '","--abc"));
    assert(invalidValueError(Param!(int[])(&config, "--abc", [1,2]), "custom suffix").isError("Invalid value '","[1, 2]","' for argument '","--abc", "custom suffix"));
}
