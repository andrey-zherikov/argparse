module argparse.internal.parsefunc;

import argparse.config;
import argparse.param;
import argparse.result;
import argparse.internal.calldispatcher;
import argparse.internal.errorhelpers;


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private struct Handler(TYPE)
{
    static Result opCall(TYPE function(string[] value) func, ref TYPE receiver, RawParam param)
    {
        receiver = func(param.value);
        return Result.Success;
    }
    static Result opCall(TYPE function(string value) func, ref TYPE receiver, RawParam param)
    {
        foreach (value; param.value)
            receiver = func(value);
        return Result.Success;
    }
    static Result opCall(TYPE function(RawParam param) func, ref TYPE receiver, RawParam param)
    {
        receiver = func(param);
        return Result.Success;
    }
    static Result opCall(Result function(ref TYPE receiver, RawParam param) func, ref TYPE receiver, RawParam param)
    {
        return func(receiver, param);
    }
    static Result opCall(bool function(ref TYPE receiver, RawParam param) func, ref TYPE receiver, RawParam param)
    {
        return func(receiver, param) ? Result.Success : processingError(param);
    }
    static Result opCall(void function(ref TYPE receiver, RawParam param) func, ref TYPE receiver, RawParam param)
    {
        func(receiver, param);
        return Result.Success;
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// T parse(string[] value)
// T parse(string value)
// T parse(RawParam param)
// Result parse(ref T receiver, RawParam param)
// bool parse(ref T receiver, RawParam param)
// void parse(ref T receiver, RawParam param)
package(argparse) struct ParseFunc(RECEIVER)
{
    alias CD = CallDispatcher!(Handler!RECEIVER);
    CD dispatcher;
    alias this = dispatcher;

    static foreach(T; CD.TYPES)
        this(T f)
        {
            dispatcher = CD(f);
        }
}

unittest
{
    auto test(T, F)(F func, string[] values)
    {
        T receiver;
        Config config;
        assert(ParseFunc!T(func)(receiver, RawParam(&config, "", values)));
        return receiver;
    }
    auto testErr(T, F)(F func, string[] values)
    {
        T receiver;
        Config config;
        return ParseFunc!T(func)(receiver, RawParam(&config, "", values));
    }

    // T parse(string value)
    assert(test!string((string a) => a, ["1","2","3"]) == "3");

    // T parse(string[] value)
    assert(test!(string[])((string[] a) => a, ["1","2","3"]) == ["1","2","3"]);

    // T parse(RawParam param)
    assert(test!string((RawParam p) => p.value[0], ["1","2","3"]) == "1");

    // Result parse(ref T receiver, RawParam param)
    assert(test!(string[])((ref string[] r, RawParam p) { r = p.value; return Result.Success; }, ["1","2","3"]) == ["1","2","3"]);
    assert(testErr!(string[])((ref string[] r, RawParam p) => Result.Error("error text"), ["1","2","3"]).isError("error text"));

    // bool parse(ref T receiver, RawParam param)
    assert(test!(string[])((ref string[] r, RawParam p) { r = p.value; return true; }, ["1","2","3"]) == ["1","2","3"]);
    assert(testErr!(string[])((ref string[] r, RawParam p) => false, ["1","2","3"]).isError("Can't process value"));

    // void parse(ref T receiver, RawParam param)
    assert(test!(string[])((ref string[] r, RawParam p) { r = p.value; }, ["1","2","3"]) == ["1","2","3"]);
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

package enum PassThrough = ParseFunc!(string[])((string[] _) => _);

unittest
{
    Config config;
    string[] s;
    PassThrough(s, Param!(string[])(&config,"",["7","8"]));
    assert(s == ["7","8"]);
}
