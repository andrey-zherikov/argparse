module argparse.internal.novalueactionfunc;

import argparse.config;
import argparse.param;
import argparse.result;
import argparse.internal.errorhelpers;

import std.meta;
import std.traits;
import std.sumtype;


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

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) struct NoValueActionFunc(RECEIVER)
{
    private struct ProcessingError
    {
        Result opCall(ref RECEIVER receiver, Param!void param) const
        {
            return processingError(param);
        }
    }

    private struct SetValue
    {
        RECEIVER value;

        this(RECEIVER v)
        {
            value = v;
        }

        Result opCall(ref RECEIVER receiver, Param!void param) const
        {
            import std.conv: to;

            receiver = value.to!RECEIVER;

            return Result.Success;
        }
    }

    alias TYPES = AliasSeq!(ProcessingError, Result function(ref RECEIVER receiver, Param!void param), SetValue);

    SumType!TYPES F;

    static foreach(T; TYPES)
    this(T func)
    {
        F = func;
    }

    bool opCast(T : bool)() const
    {
        return F != typeof(F).init;
    }

    Result opCall(ref RECEIVER receiver, Param!void param) const
    {
        return F.match!(_ => _(receiver, param));
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

package(argparse) auto SetValue(VALUE)(VALUE value)
{
    return NoValueActionFunc!VALUE(NoValueActionFunc!VALUE.SetValue(value));
    // ValueSetter!VALUE vs = { value };
    // return vs;
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
