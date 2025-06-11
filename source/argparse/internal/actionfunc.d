module argparse.internal.actionfunc;

import argparse.config;
import argparse.param;
import argparse.result;
import argparse.internal.errorhelpers;

import std.traits;
import std.sumtype;


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private struct Handler(RECEIVER, PARSE)
{
    static Result opCall(bool function(ref RECEIVER receiver, PARSE value) func, ref RECEIVER receiver, Param!PARSE param)
    {
        return func(receiver, param.value) ? Result.Success : processingError(param);
    }
    static Result opCall(void function(ref RECEIVER receiver, PARSE value) func, ref RECEIVER receiver, Param!PARSE param)
    {
        func(receiver, param.value);
        return Result.Success;
    }
    static Result opCall(Result function(ref RECEIVER receiver, PARSE value) func, ref RECEIVER receiver, Param!PARSE param)
    {
        return func(receiver, param.value);
    }
    static Result opCall(bool function(ref RECEIVER receiver, Param!PARSE param) func, ref RECEIVER receiver, Param!PARSE param)
    {
        return func(receiver, param) ? Result.Success : processingError(param);
    }
    static Result opCall(void function(ref RECEIVER receiver, Param!PARSE param) func, ref RECEIVER receiver, Param!PARSE param)
    {
        func(receiver, param);
        return Result.Success;
    }
    static Result opCall(Result function(ref RECEIVER receiver, Param!PARSE param) func, ref RECEIVER receiver, Param!PARSE param)
    {
        return func(receiver, param);
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// bool action(ref T receiver, ParseType value)
// void action(ref T receiver, ParseType value)
// Result action(ref T receiver, ParseType value)
// bool action(ref T receiver, Param!ParseType param)
// void action(ref T receiver, Param!ParseType param)
// Result action(ref T receiver, Param!ParseType param)
package(argparse) struct ActionFunc(RECEIVER, PARSE)
{
    alias getFirstParameter(T) = Parameters!T[0];
    alias TYPES = staticMap!(getFirstParameter, typeof(__traits(getOverloads, Handler!(RECEIVER, PARSE), "opCall")));

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

    Result opCall(ref RECEIVER receiver, Param!PARSE param) const
    {
        return F.match!(_ => Handler!(RECEIVER, PARSE)(_, receiver, param));
    }
}

unittest
{
    auto test(T, F)(F func, T values)
    {
        T receiver;
        Config config;
        assert(ActionFunc!(T,T)(func)(receiver, Param!T(&config, "", values)));
        return receiver;
    }
    auto testErr(T, F)(F func, T values)
    {
        T receiver;
        Config config;
        return ActionFunc!(T,T)(func)(receiver, Param!T(&config, "", values));
    }

    // Result action(ref T receiver, ParseType value)
    assert(test((ref string[] p, string[] a) { p=a; return Result.Success; }, ["1","2","3"]) == ["1","2","3"]);
    assert(testErr((ref string[] p, string[] a) => Result.Error("error text"), ["1","2","3"]).isError("error text"));

    // bool action(ref T receiver, ParseType value)
    assert(test((ref string[] p, string[] a) { p=a; return true; }, ["1","2","3"]) == ["1","2","3"]);
    assert(testErr((ref string[] p, string[] a) => false, ["1","2","3"]).isError("Can't process value"));

    // void action(ref T receiver, ParseType value)
    assert(test((ref string[] p, string[] a) { p=a; }, ["1","2","3"]) == ["1","2","3"]);

    // Result action(ref T receiver, Param!ParseType param)
    assert(test((ref string[] p, Param!(string[]) a) { p=a.value; return Result.Success; }, ["1","2","3"]) == ["1","2","3"]);
    assert(testErr((ref string[] p, Param!(string[]) a) => Result.Error("error text"), ["1","2","3"]).isError("error text"));

    // bool action(ref T receiver, Param!ParseType param)
    assert(test((ref string[] p, Param!(string[]) a) { p=a.value; return true; }, ["1","2","3"]) == ["1","2","3"]);
    assert(testErr((ref string[] p, Param!(string[]) a) => false, ["1","2","3"]).isError("Can't process value"));

    // void action(ref T receiver, Param!ParseType param)
    assert(test((ref string[] p, Param!(string[]) a) { p=a.value; }, ["1","2","3"]) == ["1","2","3"]);
}

unittest
{
    alias test = (int[] v1, int[] v2) {
        int[] res;

        Param!(int[]) param;

        enum append = ActionFunc!(int[],int[])((ref int[] _1, int[] _2) { _1 ~= _2; });

        param.value = v1;   append(res, param);

        param.value = v2;   append(res, param);

        return res;
    };
    assert(test([1,2,3],[7,8,9]) == [1,2,3,7,8,9]);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package enum Assign(TYPE) = ActionFunc!(TYPE, TYPE)
    ((ref TYPE _1, TYPE _2)
    {
        _1 = _2;
    });

unittest
{
    Config config;
    int i;
    Assign!int(i,Param!int(&config,"",7));
    assert(i == 7);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package enum Append(TYPE) = ActionFunc!(TYPE, TYPE)
    ((ref TYPE _1, TYPE _2)
    {
        _1 ~= _2;
    });

unittest
{
    Config config;
    int[] i;
    Append!(int[])(i,Param!(int[])(&config,"",[1,2,3]));
    Append!(int[])(i,Param!(int[])(&config,"",[7,8,9]));
    assert(i == [1, 2, 3, 7, 8, 9]);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package enum Extend(TYPE) = ActionFunc!(TYPE, ForeachType!TYPE)
    ((ref TYPE _1, ForeachType!TYPE _2)
    {
        _1 ~= _2;
    });

unittest
{
    Config config;
    int[][] i;
    Extend!(int[][])(i,Param!(int[])(&config,"",[1,2,3]));
    Extend!(int[][])(i,Param!(int[])(&config,"",[7,8,9]));
    assert(i == [[1,2,3],[7,8,9]]);
}
