module argparse.internal.novalueactionfunc;

import argparse.config;
import argparse.param;
import argparse.result;
import argparse.internal.errorhelpers;


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
private struct ValueSetter(VALUE)
{
    VALUE value;

    Result opCall(ref VALUE receiver, Param!void) const
    {
        import std.conv: to;

        receiver = value.to!VALUE;

        return Result.Success;
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) struct NoValueActionFunc(RECEIVER)
{
    union
    {
        Result function(ref RECEIVER, Param!void) func;
        ValueSetter!RECEIVER setter;
    }
    size_t selection = -1;
    

    this(Result function(ref RECEIVER, Param!void) f)
    {
        func = f;
        selection = 0;
    }

    this(ValueSetter!RECEIVER s)
    {
        setter = s;
        selection = 1;
    }

    bool opCast(T : bool)() const
    {
        return selection != -1;
    }

    Result opCall(ref RECEIVER receiver, Param!void param) const
    {
        switch(selection)
        {
            case 0: return func(receiver, param);
            case 1: return setter(receiver, param);
            default: assert(false);
        }
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
    assert(testErr!int((ref int r, Param!void p) => Result.Error(1, "error text")).isError("error text"));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) auto SetValue(VALUE)(VALUE value)
{
    ValueSetter!VALUE setter = { value };

    return NoValueActionFunc!VALUE(setter);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package enum CallFunctionNoParam(FUNC) = NoValueActionFunc!FUNC
    ((ref FUNC func, Param!void param)
    {
        // ... func()
        static if(is(FUNC == R function(), R) || is(FUNC == R delegate(), R))
        {
            static if(is(R == Result))
                return func();
            else
                func();
        }
        else static if(is(FUNC == R function(bool), R) || is(FUNC == R delegate(bool), R))
        {
            static if(is(R == Result))
                return func(true);
            else
                func(true);
        }
        // ... func(Param!void param)
        else static if(is(FUNC == R function(Param!void), R) || is(FUNC == R delegate(Param!void), R))
        {
            static if(is(R == Result))
                return func(param);
            else
                func(param);
        }
        // ... func(RawParam param)
        else static if(is(FUNC == R function(RawParam), R) || is(FUNC == R delegate(RawParam), R))
        {
            static if(is(R == Result))
                return func(RawParam(param.config, param.name));
            else
                func(RawParam(param.config, param.name));
        }
        // ... func(T value)
        else static if(is(FUNC == R function(T), R, T) || is(FUNC == R delegate(T), R, T))
        {
            static if(is(R == Result))
                return func(T.init);
            else
                func(T.init);
        }
        else
            static assert(false, "Unsupported callback: " ~ FUNC.stringof);

        return Result.Success;
    });
