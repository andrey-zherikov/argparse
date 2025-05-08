module argparse.internal.novalueactionfunc;

import argparse.config;
import argparse.param;
import argparse.result;
import argparse.internal.errorhelpers;


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse)
{
    // This overload also forces functions to drop their attributes, reducing the variety of types we have to handle
    auto NoValueActionFunc(T)(Result function(ref T, Param!void) func) { return func; }

    auto NoValueActionFunc(T, F)(F obj)
    if(!is(typeof(*obj) == function) && is(typeof({ T receiver; return obj(receiver, Param!void.init); }()) : Result))
    {
        return obj;
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

    // Result action(ref DEST receiver, Param!void param)
    assert(test!int((ref int r, Param!void p) { r=7; return Result.Success; }) == 7);
    assert(testErr!int((ref int r, Param!void p) => Result.Error("error text")).isError("error text"));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private struct ValueSetter(RECEIVER)
{
    RECEIVER value;

    Result opCall(ref RECEIVER receiver, Param!void) const
    {
        receiver = value;
        return Result.Success;
    }
}

package(argparse) auto SetValue(VALUE)(VALUE value)
{
    ValueSetter!VALUE vs = { value };
    return vs;
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
