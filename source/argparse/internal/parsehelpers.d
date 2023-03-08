module argparse.internal.parsehelpers;

import argparse.param;
import argparse.result;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package auto Convert(T)(string value)
{
    import std.conv: to;
    return value.length > 0 ? value.to!T : T.init;
}

unittest
{
    assert(Convert!int("7") == 7);
    assert(Convert!string("7") == "7");
    assert(Convert!char("7") == '7');
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) auto PassThrough(string[] values)
{
    return values;
}

unittest
{
    assert(PassThrough(["7","8"]) == ["7","8"]);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package auto Assign(DEST, SRC=DEST)(ref DEST param, SRC value)
{
    param  = value;
}

unittest
{
    int i;
    Assign!(int)(i,7);
    assert(i == 7);
}
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package auto Append(T)(ref T param, T value)
{
    param ~= value;
}


unittest
{
    int[] i;
    Append!(int[])(i, [1, 2, 3]);
    Append!(int[])(i, [7, 8, 9]);
    assert(i == [1, 2, 3, 7, 8, 9]);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package auto Extend(T)(ref T[] param, T value)
{
    param ~= value;
}

unittest
{
    int[][] i;
    Extend!(int[])(i,[1,2,3]);
    Extend!(int[])(i,[7,8,9]);
    assert(i == [[1,2,3],[7,8,9]]);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package auto CallFunction(F)(ref F func, RawParam param)
{
    // ... func()
    static if(__traits(compiles, { func(); }))
    {
        func();
    }
    // ... func(string value)
    else static if(__traits(compiles, { func(param.value[0]); }))
    {
        foreach(value; param.value)
            func(value);
    }
    // ... func(string[] value)
    else static if(__traits(compiles, { func(param.value); }))
    {
        func(param.value);
    }
    // ... func(RawParam param)
    else static if(__traits(compiles, { func(param); }))
    {
        func(param);
    }
    else
        static assert(false, "Unsupported callback: " ~ F.stringof);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package auto CallFunctionNoParam(F)(ref F func, Param!void param)
{
    // ... func()
    static if(__traits(compiles, { func(); }))
    {
        func();
    }
    // ... func(string value)
    else static if(__traits(compiles, { func(string.init); }))
    {
        func(string.init);
    }
    // ... func(string[] value)
    else static if(__traits(compiles, { func([]); }))
    {
        func([]);
    }
    // ... func(Param!void param)
    else static if(__traits(compiles, { func(param); }))
    {
        func(param);
    }
    // ... func(RawParam param)
    else static if(__traits(compiles, { func(RawParam.init); }))
    {
        func(RawParam(param.config, param.name));
    }
    else
        static assert(false, "Unsupported callback: " ~ F.stringof);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) template ValueInList(alias values, TYPE)
{
    static auto ValueInList(Param!TYPE param)
    {
        import std.array : assocArray, join;
        import std.range : repeat, front;
        import std.conv: to;

        enum valuesAA = assocArray(values, false.repeat);
        enum allowedValues = values.to!(string[]).join(',');

        static if(is(typeof(values.front) == TYPE))
            auto paramValues = [param.value];
        else
            auto paramValues = param.value;

        foreach(value; paramValues)
            if(!(value in valuesAA))
                return Result.Error("Invalid value '", value, "' for argument '", param.name, "'.\nValid argument values are: ", allowedValues);

        return Result.Success;
    }
    static auto ValueInList(Param!(TYPE[]) param)
    {
        foreach(ref value; param.value)
        {
            auto res = ValueInList!(values, TYPE)(Param!TYPE(param.config, param.name, value));
            if(!res)
                return res;
        }
        return Result.Success;
    }
}

unittest
{
    enum values = ["a","b","c"];

    assert(ValueInList!(values, string)(Param!string(null, "", "b")));
    assert(!ValueInList!(values, string)(Param!string(null, "", "d")));

    assert(ValueInList!(values, string)(RawParam(null, "", ["b"])));
    assert(ValueInList!(values, string)(RawParam(null, "", ["b","a"])));
    assert(!ValueInList!(values, string)(RawParam(null, "", ["d"])));
    assert(!ValueInList!(values, string)(RawParam(null, "", ["b","d"])));
}
