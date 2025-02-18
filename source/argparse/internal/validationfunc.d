module argparse.internal.validationfunc;

import argparse.config;
import argparse.param;
import argparse.result;
import argparse.internal.errorhelpers;

import std.conv;
import std.sumtype;
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



    import std.meta: AliasSeq;

    alias getFirstParameter(T) = Unqual!(Parameters!T[0]);

    alias TYPES = AliasSeq!(staticMap!(getFirstParameter, typeof(__traits(getOverloads, Handler!TYPE, "opCall"))));

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

    Result opCall(Param!TYPE param) const
    {
        return F.match!((const ref _) => Handler!TYPE(_, param));
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
