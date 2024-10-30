module argparse.internal.novalueactionfunc;

import argparse.config;
import argparse.param;
import argparse.result;
import argparse.internal.errorhelpers;

import std.traits;
import std.sumtype;


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private struct Handler(RECEIVER)
{
    static Result opCall(bool function(ref RECEIVER receiver) func, ref RECEIVER receiver, Param!void param)
    {
        return func(receiver) ? Result.Success : processingError(param);
    }
    static Result opCall(void function(ref RECEIVER receiver) func, ref RECEIVER receiver, Param!void param)
    {
        func(receiver);
        return Result.Success;
    }
    static Result opCall(Result function(ref RECEIVER receiver) func, ref RECEIVER receiver, Param!void param)
    {
        return func(receiver);
    }
    static Result opCall(bool function(ref RECEIVER receiver, Param!void param) func, ref RECEIVER receiver, Param!void param)
    {
        return func(receiver, param) ? Result.Success : processingError(param);
    }
    static Result opCall(void function(ref RECEIVER receiver, Param!void param) func, ref RECEIVER receiver, Param!void param)
    {
        func(receiver, param);
        return Result.Success;
    }
    static Result opCall(Result function(ref RECEIVER receiver, Param!void param) func, ref RECEIVER receiver, Param!void param)
    {
        return func(receiver, param);
    }
}

// bool action(ref DEST receiver)
// void action(ref DEST receiver)
// Result action(ref DEST receiver)
// bool action(ref DEST receiver, Param!void param)
// void action(ref DEST receiver, Param!void param)
// Result action(ref DEST receiver, Param!void param)
package(argparse) struct NoValueActionFunc(RECEIVER)
{
    alias getFirstParameter(T) = Parameters!T[0];
    alias TYPES = staticMap!(getFirstParameter, typeof(__traits(getOverloads, Handler!RECEIVER, "opCall")));

    SumType!TYPES F;

    static foreach(T; TYPES)
    this(T func)
    {
        F = func;
    }

    static foreach(T; TYPES)
    auto opAssign(T func)
    {
        F = func;
    }

    bool opCast(T : bool)() const
    {
        return F != typeof(F).init;
    }

    Result opCall(ref RECEIVER receiver, Param!void param) const
    {
        return F.match!(_ => Handler!RECEIVER(_, receiver, param));
    }
}

unittest
{
    auto test(T, F)(F func)
    {
        T receiver;
        assert(NoValueActionFunc!T(func)(receiver, Param!void.init));
        return receiver;
    }
    auto testErr(T, F)(F func)
    {
        T receiver;
        return NoValueActionFunc!T(func)(receiver, Param!void.init);
    }

    // Result action(ref DEST receiver)
    assert(test!int((ref int r) { r=7; return Result.Success; }) == 7);
    assert(testErr!int((ref int r) => Result.Error("error text")).isError("error text"));

    // bool action(ref DEST receiver)
    assert(test!int((ref int p) { p=7; return true; }) == 7);
    assert(testErr!int((ref int p) => false).isError("Can't process value"));

    // void action(ref DEST receiver)
    assert(test!int((ref int p) { p=7; }) == 7);

    // Result action(ref DEST receiver, Param!void param)
    assert(test!int((ref int r, Param!void p) { r=7; return Result.Success; }) == 7);
    assert(testErr!int((ref int r, Param!void p) => Result.Error("error text")).isError("error text"));

    // bool action(ref DEST receiver, Param!void param)
    assert(test!int((ref int r, Param!void p) { r=7; return true; }) == 7);
    assert(testErr!int((ref int r, Param!void p) => false).isError("Can't process value"));

    // void action(ref DEST receiver, Param!void param)
    assert(test!int((ref int r, Param!void p) { r=7; }) == 7);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package enum CallFunctionNoParam(FUNC) = NoValueActionFunc!FUNC
    ((ref FUNC func, Param!void param)
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
            static assert(false, "Unsupported callback: " ~ FUNC.stringof);

        return Result.Success;
    });
