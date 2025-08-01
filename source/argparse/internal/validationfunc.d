module argparse.internal.validationfunc;

import argparse.config;
import argparse.param;
import argparse.result;
import argparse.internal.calldispatcher;
import argparse.internal.errorhelpers;

import std.conv: to;
import std.traits;


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private struct Handler(TYPE)
{
    static Result opCall(bool function(TYPE value) func, Param!TYPE param)
    {
        return func(param.value) ? Result.Success : invalidValueError(param);
    }
    static Result opCall(Result function(TYPE value) func, Param!TYPE param)
    {
        return func(param.value);
    }
    static Result opCall(bool function(Param!TYPE param) func, Param!TYPE param)
    {
        return func(param) ? Result.Success : invalidValueError(param);
    }
    static Result opCall(Result function(Param!TYPE param) func, Param!TYPE param)
    {
        return func(param);
    }
    static Result opCall(bool function(Param!(TYPE[]) param) func, Param!TYPE param)
    {
        return func(Param!(TYPE[])(param.config, param.name, [param.value])) ? Result.Success : invalidValueError(param);
    }
    static Result opCall(Result function(Param!(TYPE[]) param) func, Param!TYPE param)
    {
        return func(Param!(TYPE[])(param.config, param.name, [param.value]));
    }
    static Result opCall(const ref ValidationFunc!TYPE.ValueInList func, Param!TYPE param)
    {
        return func(param);
    }

    static if(isArray!TYPE)
    {
        static Result opCall(bool function(ForeachType!TYPE value) func, Param!TYPE param)
        {
            foreach(value; param.value)
                if(!func(value))
                    return invalidValueError(param);
            return Result.Success;
        }
        static Result opCall(Result function(ForeachType!TYPE value) func, Param!TYPE param)
        {
            foreach (value; param.value)
            {
                Result res = func(value);
                if (!res)
                    return res;
            }
            return Result.Success;
        }
    }
}

// bool validate(T value)
// bool validate(T[] value)
// bool validate(Param!T param)
// Result validate(T value)
// Result validate(T[] value)
// Result validate(Param!T param)
package(argparse) struct ValidationFunc(TYPE)
{
    private struct ValueInList
    {
        bool[TYPE] values;

        this(TYPE[] values)
        {
            foreach(v; values)
                this.values[v.to!(immutable(TYPE))] = false;
        }


        Result opCall(Param!TYPE param) const
        {
            if(!(param.value in values))
            {
                import std.algorithm : map;
                import std.array : join;

                auto valueStyle = param.isNamedArg ? param.config.styling.namedArgumentValue : param.config.styling.positionalArgumentValue;

                string valuesList = values.keys.map!(_ => valueStyle(_.to!string)).join(",");

                return invalidValueError(param,
                    "\nValid argument values are: " ~ valuesList);
            }

            return Result.Success;
        }
    }

    alias CD = CallDispatcher!(Handler!TYPE);
    CD dispatcher;

    static foreach(T; CD.TYPES)
    this(T f)
    {
        dispatcher = CD(f);
    }

    bool opCast(T : bool)() const
    {
        return dispatcher != CD.init;
    }

    Result opCall(Param!TYPE param) const
    {
        return dispatcher.opCall(param);
    }

    Result opCall(Param!(TYPE[]) param) const
    {
        foreach(ref value; param.value)
        {
            auto res = opCall(Param!TYPE(param.config, param.name, value));
            if(!res)
                return res;
        }
        return Result.Success;
    }
}

unittest
{
    Config config;
    auto fs = ValidationFunc!string((string s) => s.length > 0);
    assert(!fs(Param!string(&config, "", "")));
    assert(fs(Param!string(&config, "", "a")));

    auto fsa = ValidationFunc!(string[2])((string s) => s.length > 0);
    assert(!fsa(Param!(string[2])(&config, "", ["ab", ""])));
    assert(fsa(Param!(string[2])(&config, "", ["a", "cd"])));

    auto fi = ValidationFunc!int((int x) => bool(x & 0x1));
    assert(!fi(Param!int(&config, "", 8)));
    assert(fi(Param!int(&config, "", 13)));

    auto fa = ValidationFunc!(int[])((int x) => bool(x & 0x1));
    assert(!fa(Param!(int[])(&config, "", [3, 8])));
    assert(fa(Param!(int[])(&config, "", [13, -1])));
}

unittest
{
    auto test(T, F)(F func, T[] values)
    {
        Config config;
        return ValidationFunc!(T[])(func)(Param!(T[])(&config, "", values));
    }

    // Result validate(Param!T param)
    assert(test((RawParam _) => Result.Success, ["1","2","3"]));
    assert(test((RawParam _) => Result.Error("error text"), ["1","2","3"]).isError("error text"));

    // bool validate(Param!T param)
    assert(test((RawParam _) => true, ["1","2","3"]));
    assert(test((RawParam _) => false, ["1","2","3"]).isError("Invalid value"));

    // Result validate(Param!(T[]) param)
    assert(test((Param!(string[][]) _) => Result.Success, ["1","2","3"]));
    assert(test((Param!(string[][]) _) => Result.Error("error text"), ["1","2","3"]).isError("error text"));

    // bool validate(Param!(T[]) param)
    assert(test((Param!(string[][]) _) => true, ["1","2","3"]));
    assert(test((Param!(string[][]) _) => false, ["1","2","3"]).isError("Invalid value"));

    // Result validate(T value)
    assert(test((string _) => Result.Success, ["1","2","3"]));
    assert(test((string _) => Result.Error("error text"), ["1","2","3"]).isError("error text"));

    // bool validate(T value)
    assert(test((string _) => true, ["1","2","3"]));
    assert(test((string _) => false, ["1","2","3"]).isError("Invalid value"));

    // Result validate(T[] value)
    assert(test((string[] _) => Result.Success, ["1","2","3"]));
    assert(test((string[] _) => Result.Error("error text"), ["1","2","3"]).isError("error text"));

    // bool validate(T[] value)
    assert(test((string[] _) => true, ["1","2","3"]));
    assert(test((string[] _) => false, ["1","2","3"]).isError("Invalid value"));
}

unittest
{
    auto test(T, F)(F func, T[] values)
    {
        Config config;
        return ValidationFunc!(T[])(func)(Param!(T[])(&config, "--argname", values));
    }

    // Result validate(Param!T param)
    assert(test((RawParam _) => Result.Success, ["1","2","3"]));
    assert(test((RawParam _) => Result.Error("error text"), ["1","2","3"]).isError("error text"));

    // bool validate(Param!T param)
    assert(test((RawParam _) => true, ["1","2","3"]));
    assert(test((RawParam _) => false, ["1","2","3"]).isError("Invalid value","for argument","--argname"));

    // Result validate(T value)
    assert(test((string _) => Result.Success, ["1","2","3"]));
    assert(test((string _) => Result.Error("error text"), ["1","2","3"]).isError("error text"));

    // bool validate(T value)
    assert(test((string _) => true, ["1","2","3"]));
    assert(test((string _) => false, ["1","2","3"]).isError("Invalid value","for argument","--argname"));

    // Result validate(T[] value)
    assert(test((string[] _) => Result.Success, ["1","2","3"]));
    assert(test((string[] _) => Result.Error("error text"), ["1","2","3"]).isError("error text"));

    // bool validate(T[] value)
    assert(test((string[] _) => true, ["1","2","3"]));
    assert(test((string[] _) => false, ["1","2","3"]).isError("Invalid value","for argument","--argname"));
}

unittest
{
    auto test(T, F)(F func)
    {
        Config config;
        return ValidationFunc!F(func)(RawParam(&config, "", ["1","2","3"]));
    }

    static assert(!__traits(compiles, { test!(string[])(() {}); }));
    static assert(!__traits(compiles, { test!(string[])((int,int) {}); }));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package enum Pass(TYPE) = ValidationFunc!TYPE((TYPE _) => true);

unittest
{
    assert(Pass!int(Param!int.init));
    assert(Pass!string(Param!string.init));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) auto ValueInList(TYPE)(TYPE[] values...)
{
    alias VF = ValidationFunc!TYPE;
    return VF(VF.ValueInList(values));
}

unittest
{
    enum values = ["a","b","c"];

    import argparse.config;
    Config config;

    assert(ValueInList(values)(Param!string(&config, "", "b")));
    assert(!ValueInList(values)(Param!string(&config, "", "d")));

    assert(ValueInList(values)(RawParam(&config, "", ["b"])));
    assert(ValueInList(values)(RawParam(&config, "", ["b","a"])));
    assert(!ValueInList(values)(RawParam(&config, "", ["d"])));
    assert(!ValueInList(values)(RawParam(&config, "", ["b","d"])));
}
