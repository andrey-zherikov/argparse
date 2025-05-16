module argparse.internal.validationfunc;

import argparse.config;
import argparse.param;
import argparse.result;
import argparse.internal.errorhelpers;

import std.conv: to;


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private struct FuncValidator(T, int strategy, F)
{
    F func;

    Result opCall(Param!T param) const
    {
        static if(strategy == 0)
            return func(param) ? Result.Success : invalidValueError(param);
        else static if(strategy == 1)
            return func(param.value);
        else static if(strategy == 2)
            return func(param.value) ? Result.Success : invalidValueError(param);
        else static if(strategy == 3 || strategy == 4)
        {
            T[1] values = [param.value];
            auto arrParam = Param!(T[])(param.config, param.name, values[]);

            static if(strategy == 3)
                return func(arrParam);
            else
                return func(arrParam) ? Result.Success : invalidValueError(param);
        }
        else
        {
            foreach(value; param.value)
                static if(strategy == 5)
                {
                    Result res = func(value);
                    if(!res)
                        return res;
                }
                else
                    if(!func(value))
                        return invalidValueError(param);
            return Result.Success;
        }
    }
}

private auto toFuncValidator(T, int strategy, F)(F func)
{
    FuncValidator!(T, strategy, F) val = { func };
    return val;
}

package(argparse)
{
    // These overloads also force functions to drop their attributes, reducing the variety of types we have to handle
    auto ValidationFunc(T)(Result function(Param!T) func)     { return func; }
    auto ValidationFunc(T)(bool   function(Param!T) func)     { return func.toFuncValidator!(T, 0); }
    auto ValidationFunc(T)(Result function(T) func)           { return func.toFuncValidator!(T, 1); }
    auto ValidationFunc(T)(bool   function(T) func)           { return func.toFuncValidator!(T, 2); }
    auto ValidationFunc(T)(Result function(Param!(T[])) func) { return func.toFuncValidator!(T, 3); }
    auto ValidationFunc(T)(bool   function(Param!(T[])) func) { return func.toFuncValidator!(T, 4); }
    auto ValidationFunc(T : U[], U)(Result function(U) func)  { return func.toFuncValidator!(T, 5); }
    auto ValidationFunc(T : U[], U)(bool function(U) func)    { return func.toFuncValidator!(T, 6); }

    auto ValidationFunc(T, F)(F obj)
    if(!is(typeof(*obj) == function) && is(typeof(obj(Param!T.init)) : Result))
    {
        return obj;
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

package(argparse) Result validateAll(V, T)(const V validate, Param!(T[]) param) {
    foreach(ref value; param.value)
    {
        auto res = validate(Param!T(param.config, param.name, value));
        if(!res)
            return res;
    }
    return Result.Success;
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

private struct ListValidator(TYPE)
{
    bool[TYPE] values;

    Result opCall(Param!TYPE param) const
    {
        if(!(param.value in values))
        {
            import std.algorithm : map;
            import std.array : join;

            auto valueStyle = param.isNamedArg ? (
                param.config.styling.namedArgumentValue
            ) : param.config.styling.positionalArgumentValue;

            string valuesList = values.keys.map!(_ => valueStyle(_.to!string)).join(",");

            return invalidValueError(param,
                "\nValid argument values are: " ~ valuesList);
        }

        return Result.Success;
    }
}

package(argparse) auto ValueInList(TYPE)(const(TYPE)[] values...)
{
    ListValidator!TYPE result;

    foreach(v; values)
        result.values[v.to!(immutable TYPE)] = false;

    return result;
}

unittest
{
    immutable values = ["a","b","c"];

    import argparse.config;
    Config config;

    assert(ValueInList(values)(Param!string(&config, "", "b")));
    assert(!ValueInList(values)(Param!string(&config, "", "d")));

    assert(ValueInList(values).validateAll(RawParam(&config, "", ["b"])));
    assert(ValueInList(values).validateAll(RawParam(&config, "", ["b","a"])));
    assert(!ValueInList(values).validateAll(RawParam(&config, "", ["d"])));
    assert(!ValueInList(values).validateAll(RawParam(&config, "", ["b","d"])));
}
