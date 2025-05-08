module argparse.internal.parsefunc;

import argparse.config;
import argparse.param;
import argparse.result;
import argparse.internal.errorhelpers;


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private struct FuncParser(T, int strategy, F)
{
    F func;

    Result opCall(ref T receiver, RawParam param) const
    {
        static if(strategy == 0)
        {
            if(!func(receiver, param))
                return processingError(param);
        }
        else static if(strategy == 1)
            func(receiver, param);
        else static if(strategy == 2)
            receiver = func(param);
        else static if(strategy == 3)
            receiver = func(param.value);
        else
            foreach(value; param.value)
                receiver = func(value); // Only the last result is retained

        return Result.Success;
    }
}

private auto toFuncParser(T, int strategy, F)(F func)
{
    FuncParser!(T, strategy, F) p = { func };
    return p;
}

package(argparse)
{
    // These overloads also force functions to drop their attributes, reducing the variety of types we have to handle
    auto ParseFunc(T)(Result function(ref T, RawParam) func) { return func; }
    auto ParseFunc(T)(bool   function(ref T, RawParam) func) { return func.toFuncParser!(T, 0); }
    auto ParseFunc(T)(void   function(ref T, RawParam) func) { return func.toFuncParser!(T, 1); }
    auto ParseFunc(T)(T function(RawParam) func)             { return func.toFuncParser!(T, 2); }
    auto ParseFunc(T)(T function(string[]) func)             { return func.toFuncParser!(T, 3); }
    auto ParseFunc(T)(T function(string) func)               { return func.toFuncParser!(T, 4); }

    auto ParseFunc(T, F)(F obj)
    if(!is(typeof(*obj) == function) && is(typeof({ T receiver; return obj(receiver, RawParam.init); }()) : Result))
    {
        return obj;
    }
}

unittest
{
    size_t receiver;
    Config config;
    auto f = ParseFunc!size_t((const(string)[] values) => values.length);
    assert(f(receiver, RawParam(&config, "", ["abc", "def"])));
    assert(receiver == 2);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package enum Convert(TYPE) = ParseFunc!TYPE
    ((ref TYPE receiver, RawParam param)
    {
        try
        {
            import std.conv: to;

            foreach (value; param.value)
                receiver = value.length > 0 ? value.to!TYPE : TYPE.init;

            return Result.Success;
        }
        catch(Exception e)
        {
            return Result.Error(e.msg);
        }
    });

unittest
{
    alias test(T) = (string value)
    {
        T receiver;
        assert(Convert!T(receiver, RawParam(null, "", [value])));
        return receiver;
    };

    assert(test!int("7") == 7);
    assert(test!string("7") == "7");
    assert(test!char("7") == '7');
}

unittest
{
    alias testErr(T) = (string value)
    {
        T receiver;
        return Convert!T(receiver, RawParam(null, "", [value]));
    };

    assert(testErr!int("unknown").isError());
    assert(testErr!bool("unknown").isError());
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// has to do this way otherwise DMD compiler chokes - linker reports unresolved symbol for lambda:
// Error: undefined reference to `pure nothrow @nogc @safe immutable(char)[][] argparse.internal.parsefunc.__lambda12(immutable(char)[][])`
//       referenced from `pure nothrow @nogc @safe argparse.internal.valueparser.ValueParser!(immutable(char)[][], void delegate()).ValueParser argparse.internal.valueparser.ValueParser!(void, void).ValueParser.addReceiverTypeDefaults!(void delegate()).addReceiverTypeDefaults()`
// TODO: Investigate
private enum PassThroughImpl(TYPE) = ParseFunc!TYPE
    ((TYPE value)
    {
        return value;
    });

package enum PassThrough = PassThroughImpl!(string[]);

unittest
{
    Config config;
    string[] s;
    PassThrough(s, Param!(string[])(&config,"",["7","8"]));
    assert(s == ["7","8"]);
}
