module argparse.internal.valueparser;

import argparse.config;
import argparse.param;
import argparse.result;
import argparse.internal.parsehelpers;
import argparse.internal.enumhelpers: getEnumValues, getEnumValue;

import std.traits;


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private Result processingError(T)(Param!T param, string prefix = "Can't process value")
{
    import std.conv: to;
    import std.array: appender;

    auto a = appender!string(prefix);

    static if(is(typeof(param.value)))
    {
        a ~= " '";
        a ~= param.config.styling.positionalArgumentValue(param.value.to!string);
        a ~= "'";
    }

    if(param.name.length > 0 && param.name[0] == param.config.namedArgPrefix)
    {
        a ~= " for argument '";
        a ~= param.config.styling.argumentName(param.name);
        a ~= "'";
    }

    return Result.Error(a[]);
}

unittest
{
    Config config;
    assert(processingError(Param!void(&config, "")).isError("Can't process value"));
    assert(processingError(Param!void(&config, "--abc")).isError("Can't process value for argument","--abc"));
    assert(processingError(Param!(int[])(&config, "", [1,2])).isError("Can't process value '","[1, 2]"));
    assert(processingError(Param!(int[])(&config, "--abc", [1,2])).isError("Can't process value '","[1, 2]","' for argument '","--abc"));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) struct ValueParser(alias PreProcess,
                                     alias PreValidation,
                                     alias Parse,
                                     alias Validation,
                                     alias Action,
                                     alias NoValueAction)
{
    alias PreProcessArg = PreProcess;
    alias PreValidationArg = PreValidation;
    alias ParseArg = Parse;
    alias ValidationArg = Validation;
    alias ActionArg = Action;
    alias NoValueActionArg = NoValueAction;

    alias changePreProcess   (alias func) = ValueParser!(      func, PreValidation, Parse, Validation, Action, NoValueAction);
    alias changePreValidation(alias func) = ValueParser!(PreProcess,          func, Parse, Validation, Action, NoValueAction);
    alias changeParse        (alias func) = ValueParser!(PreProcess, PreValidation,  func, Validation, Action, NoValueAction);
    alias changeValidation   (alias func) = ValueParser!(PreProcess, PreValidation, Parse,       func, Action, NoValueAction);
    alias changeAction       (alias func) = ValueParser!(PreProcess, PreValidation, Parse, Validation,   func, NoValueAction);
    alias changeNoValueAction(alias func) = ValueParser!(PreProcess, PreValidation, Parse, Validation, Action,          func);

    template addDefaults(DefaultParseFunctions)
    {
        template Get(string symbol)
        {
            alias M = mixin(symbol);
            static if(is(M == void))
                alias Get = __traits(getMember, DefaultParseFunctions, symbol);
            else
                alias Get = M;
        }

        alias addDefaults = ValueParser!(
            Get!"PreProcessArg",
            Get!"PreValidationArg",
            Get!"ParseArg",
            Get!"ValidationArg",
            Get!"ActionArg",
            Get!"NoValueActionArg",
        );
    }


    // Procedure to process (parse) the values to an argument of type T
    //  - if there is a value(s):
    //      - pre validate raw strings
    //      - parse raw strings
    //      - validate parsed values
    //      - action with values
    //  - if there is no value:
    //      - action if no value
    // Requirement: rawValues.length must be correct
    static Result parse(T)(ref T receiver, RawParam param)
    {
        return addDefaults!(TypedValueParser!T).addDefaults!DefaultValueParser.parseImpl(receiver, param);
    }
    static Result parseImpl(T)(ref T receiver, ref RawParam rawParam)
    {
        alias preValidation = ValidateFunc!(PreValidation, "Pre validation");
        alias parse         = ParseFunc!Parse;
        alias ParseType     = parse.ReturnType;
        alias validation    = ValidateFunc!Validation;
        alias action        = ActionFunc!Action;
        alias noValueAction = NoValueActionFunc!NoValueAction;

        if(rawParam.value.length == 0)
        {
            return noValueAction(receiver, Param!void(rawParam.config, rawParam.name));
        }
        else
        {
            PreProcess(rawParam);

            Result res = preValidation(rawParam);
            if(!res)
                return res;

            auto parsedParam = Param!ParseType(rawParam.config, rawParam.name);

            res = parse(parsedParam.value, rawParam);
            if(!res)
                return res;

            res = validation(parsedParam);
            if(!res)
                return res;

            res = action(receiver, parsedParam);
            if(!res)
                return res;

            return Result.Success;
        }
    }
}


unittest
{
    int receiver;
    assert(ValueParser!(void, void, (ref int i, RawParam p) => Result.Error("test error"), void, Assign, void).parse(receiver, RawParam(null,"",[""])).isError("test error"));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private alias DefaultValueParser = ValueParser!(
    (_) {},                 // pre process
    _ => Result.Success,    // pre validate
    void,                   // parse
    _ => Result.Success,    // validate
    (ref receiver, value) => Assign(receiver, value),           // action
    (ref receiver, Param!void param) => processingError(param)  // no-value action
);

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private template TypedValueParser(T)
if(!is(T == void))
{
    import std.conv: to;

    static if(is(T == enum))
    {
        alias TypedValueParser = ValueParser!(
            void,   // pre process
            ValueInList!(getEnumValues!T, typeof(RawParam.value)),   // pre validate
            getEnumValue!T,   // parse
            void,   // validate
            void,   // action
            void    // no-value action
        );
    }
    else static if(isSomeString!T || isNumeric!T)
    {
        alias TypedValueParser = ValueParser!(
            void,       // pre process
            void,       // pre validate
            Convert!T,  // parse
            void,       // validate
            void,       // action
            void        // no-value action
        );
    }
    else static if(isBoolean!T)
    {
        alias TypedValueParser = ValueParser!(
            void,                               // pre process
            void,                               // pre validate
            (string value)                      // parse
            {
                switch(value)
                {
                    case "":    goto case;
                    case "yes": goto case;
                    case "y":   return true;
                    case "no":  goto case;
                    case "n":   return false;
                    default:    return value.to!T;
                }
            },
            void,                               // validate
            void,                               // action
            (ref T result) { result = true; }   // no-value action
        );
    }
    else static if(isSomeChar!T)
    {
        alias TypedValueParser = ValueParser!(
            void,                         // pre process
            void,                         // pre validate
            (string value)                // parse
            {
                return value.length > 0 ? value[0].to!T : T.init;
            },
            void,                         // validate
            void,                         // action
            void                          // no-value action
        );
    }
    else static if(isArray!T)
    {
        alias TElement = ForeachType!T;

        static if(!isArray!TElement || isSomeString!TElement)  // 1D array
        {
            static if(!isStaticArray!T)
                alias action = Append!T;
            else
                alias action = Assign!T;

            alias TypedValueParser =
                TypedValueParser!TElement
                .changePreProcess!splitValues
                .changeParse!((ref T receiver, RawParam param)
                {
                    static if(!isStaticArray!T)
                    {
                        if(receiver.length < param.value.length)
                            receiver.length = param.value.length;
                    }

                    foreach(i, value; param.value)
                    {
                        if(!TypedValueParser!TElement.parse(receiver[i],
                        RawParam(param.config, param.name, [value])))
                            return false;
                    }

                    return true;
                })
                .changeAction!(action)
                .changeNoValueAction!((ref T param) {});
        }
        else static if(!isArray!(ForeachType!TElement) || isSomeString!(ForeachType!TElement))  // 2D array
        {
            alias TypedValueParser =
                TypedValueParser!TElement
                .changeAction!(Extend!TElement)
                .changeNoValueAction!((ref T param) { param ~= TElement.init; });
        }
        else
            static assert(false, "Multi-dimentional arrays are not supported: " ~ T.stringof);
    }
    else static if(isAssociativeArray!T)
    {
        import std.string : indexOf;
        alias TypedValueParser = ValueParser!(
            splitValues,                               // pre process
            void,                                      // pre validate
            PassThrough,                               // parse
            void,                                      // validate
            (ref T recepient, Param!(string[]) param)  // action
            {
                alias K = KeyType!T;
                alias V = ValueType!T;

                foreach(input; param.value)
                {
                    auto j = indexOf(input, param.config.assignChar);
                    if(j < 0)
                        return false;

                    K key;
                    if(!TypedValueParser!K.parse(key, RawParam(param.config, param.name, [input[0 .. j]])))
                        return false;

                    V value;
                    if(!TypedValueParser!V.parse(value, RawParam(param.config, param.name, [input[j + 1 .. $]])))
                        return false;

                    recepient[key] = value;
                }
                return true;
            },
            (ref T param) {}    // no-value action
        );
    }
    else static if(is(T == function) || is(T == delegate) || is(typeof(*T) == function) || is(typeof(*T) == delegate))
    {
        alias TypedValueParser = ValueParser!(
            void,                   // pre process
            void,                   // pre validate
            PassThrough,            // parse
            void,                   // validate
            CallFunction!T,         // action
            CallFunctionNoParam!T   // no-value action
        );
    }
    else
    {
        alias TypedValueParser = ValueParser!(
            void,   // pre process
            void,   // pre validate
            void,   // parse
            void,   // validate
            void,   // action
            void    // no-value action
        );
    }
}

unittest
{
    enum MyEnum { foo, bar, }

    import std.meta: AliasSeq;
    static foreach(T; AliasSeq!(string, bool, int, double, char, MyEnum))
        static foreach(R; AliasSeq!(T, T[], T[][]))
        {{
            // ensure that this compiles
            R receiver;
            Config config;
            TypedValueParser!R.parse(receiver, RawParam(&config, "", [""]));
        }}
}

unittest
{
    alias test(R) = (string[][] values)
    {
        auto config = Config('=', ',');
        R receiver;
        foreach(value; values)
        {
            assert(TypedValueParser!R.parse(receiver, RawParam(&config, "", value)));
        }
        return receiver;
    };

    static assert(test!(string[])([["1","2","3"], [], ["4"]]) == ["1","2","3","4"]);
    static assert(test!(string[][])([["1","2","3"], [], ["4"]]) == [["1","2","3"],[],["4"]]);

    static assert(test!(string[string])([["a=bar","b=foo"], [], ["b=baz","c=boo"]]) == ["a":"bar", "b":"baz", "c":"boo"]);

    static assert(test!(string[])([["1,2,3"], [], ["4"]]) == ["1","2","3","4"]);
    static assert(test!(string[string])([["a=bar,b=foo"], [], ["b=baz,c=boo"]]) == ["a":"bar", "b":"baz", "c":"boo"]);

    static assert(test!(int[])([["1","2","3"], [], ["4"]]) == [1,2,3,4]);
    static assert(test!(int[][])([["1","2","3"], [], ["4"]]) == [[1,2,3],[],[4]]);

}

unittest
{
    import std.math: isNaN;
    enum MyEnum { foo, bar, }

    alias test(T) = (string[] values)
    {
        T receiver;
        Config config;
        assert(TypedValueParser!T.parse(receiver, RawParam(&config, "", values)));
        return receiver;
    };

    assert(test!string([""]) == "");
    assert(test!string(["foo"]) == "foo");
    assert(isNaN(test!double([""])));
    assert(test!double(["-12.34"]) == -12.34);
    assert(test!double(["12.34"]) == 12.34);
    assert(test!uint(["1234"]) == 1234);
    assert(test!int([""]) == int.init);
    assert(test!int(["-1234"]) == -1234);
    assert(test!char([""]) == char.init);
    assert(test!char(["f"]) == 'f');
    assert(test!bool([]) == true);
    assert(test!bool([""]) == true);
    assert(test!bool(["yes"]) == true);
    assert(test!bool(["y"]) == true);
    assert(test!bool(["true"]) == true);
    assert(test!bool(["no"]) == false);
    assert(test!bool(["n"]) == false);
    assert(test!bool(["false"]) == false);
    assert(test!MyEnum(["foo"]) == MyEnum.foo);
    assert(test!MyEnum(["bar"]) == MyEnum.bar);
    assert(test!(MyEnum[])(["bar","foo"]) == [MyEnum.bar, MyEnum.foo]);
    assert(test!(string[string])(["a=bar","b=foo"]) == ["a":"bar", "b":"foo"]);
    assert(test!(MyEnum[string])(["a=bar","b=foo"]) == ["a":MyEnum.bar, "b":MyEnum.foo]);
    assert(test!(int[MyEnum])(["bar=3","foo=5"]) == [MyEnum.bar:3, MyEnum.foo:5]);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// bool validate(T value)
// bool validate(T[] value)
// bool validate(Param!T param)
// Result validate(T value)
// Result validate(T[] value)
// Result validate(Param!T param)
private struct ValidateFunc(alias F, string funcName="Validation")
{
    static Result invalidValue(T)(Param!T param)
    {
        return processingError(param, "Invalid value");
    }

    static Result opCall(T)(Param!T param)
    {
        // Result validate(Param!T param)
        static if(__traits(compiles, { Result res = F(param); }))
        {
            return F(param);
        }
        // bool validate(Param!T param)
        else static if(__traits(compiles, { F(param); }))
        {
            return F(param) ? Result.Success : invalidValue(param);
        }
        // Result validate(T value)
        else static if(__traits(compiles, { Result res = F(param.value); }))
        {
            return F(param.value);
        }
        // bool validate(T value)
        else static if(__traits(compiles, { F(param.value); }))
        {
            return F(param.value) ? Result.Success : invalidValue(param);
        }
        // Result validate(T[] value)
        else static if(__traits(compiles, { Result res = F(param.value[0]); }))
        {
            foreach(value; param.value)
            {
                Result res = F(value);
                if(!res)
                    return res;
            }
            return Result.Success;
        }
        // bool validate(T[] value)
        else static if(__traits(compiles, { F(param.value[0]); }))
        {
            foreach(value; param.value)
                if(!F(value))
                    return invalidValue(param);
            return Result.Success;
        }
        else
            static assert(false, funcName~" function is not supported for type "~T.stringof~": "~typeof(F).stringof);
    }
}

unittest
{
    auto test(alias F, T)(T[] values)
    {
        Config config;
        return ValidateFunc!F(Param!(T[])(&config, "", values));
    }

    // Result validate(Param!T param)
    assert(test!((RawParam _) => Result.Success)(["1","2","3"]));
    assert(test!((RawParam _) => Result.Error("error text"))(["1","2","3"]).isError("error text"));

    // bool validate(Param!T param)
    assert(test!((RawParam _) => true)(["1","2","3"]));
    assert(test!((RawParam _) => false)(["1","2","3"]).isError("Invalid value"));

    // Result validate(T value)
    assert(test!((string _) => Result.Success)(["1","2","3"]));
    assert(test!((string _) => Result.Error("error text"))(["1","2","3"]).isError("error text"));

    // bool validate(T value)
    assert(test!((string _) => true)(["1","2","3"]));
    assert(test!((string _) => false)(["1","2","3"]).isError("Invalid value"));

    // Result validate(T[] value)
    assert(test!((string[] _) => Result.Success)(["1","2","3"]));
    assert(test!((string[] _) => Result.Error("error text"))(["1","2","3"]).isError("error text"));

    // bool validate(T[] value)
    assert(test!((string[] _) => true)(["1","2","3"]));
    assert(test!((string[] _) => false)(["1","2","3"]).isError("Invalid value"));
}

unittest
{
    auto test(alias F, T)(T[] values)
    {
        Config config;
        return ValidateFunc!F(Param!(T[])(&config, "--argname", values));
    }

    // Result validate(Param!T param)
    assert(test!((RawParam _) => Result.Success)(["1","2","3"]));
    assert(test!((RawParam _) => Result.Error("error text"))(["1","2","3"]).isError("error text"));

    // bool validate(Param!T param)
    assert(test!((RawParam _) => true)(["1","2","3"]));
    assert(test!((RawParam _) => false)(["1","2","3"]).isError("Invalid value","for argument","--argname"));

    // Result validate(T value)
    assert(test!((string _) => Result.Success)(["1","2","3"]));
    assert(test!((string _) => Result.Error("error text"))(["1","2","3"]).isError("error text"));

    // bool validate(T value)
    assert(test!((string _) => true)(["1","2","3"]));
    assert(test!((string _) => false)(["1","2","3"]).isError("Invalid value","for argument","--argname"));

    // Result validate(T[] value)
    assert(test!((string[] _) => Result.Success)(["1","2","3"]));
    assert(test!((string[] _) => Result.Error("error text"))(["1","2","3"]).isError("error text"));

    // bool validate(T[] value)
    assert(test!((string[] _) => true)(["1","2","3"]));
    assert(test!((string[] _) => false)(["1","2","3"]).isError("Invalid value","for argument","--argname"));
}

unittest
{
    auto test(alias F, T)()
    {
        Config config;
        return ValidateFunc!F(RawParam(&config, "", ["1","2","3"]));
    }

    static assert(!__traits(compiles, { test!(() {}, string[]); }));
    static assert(!__traits(compiles, { test!((int,int) {}, string[]); }));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// DEST action()
// bool action(ref DEST receiver)
// void action(ref DEST receiver)
// Result action(ref DEST receiver)
// bool action(ref DEST receiver, Param!void param)
// void action(ref DEST receiver, Param!void param)
// Result action(ref DEST receiver, Param!void param)
package struct NoValueActionFunc(alias F)
{
    static Result opCall(T)(ref T receiver, Param!void param)
    {
        // DEST action()
        static if(__traits(compiles, { receiver = cast(T) F(); }))
        {
            receiver = cast(T) F();
            return Result.Success;
        }
        // Result action(ref DEST receiver)
        else static if(__traits(compiles, { Result res = F(receiver); }))
        {
            return F(receiver);
        }
        // bool action(ref DEST receiver)
        else static if(__traits(compiles, { auto res = cast(bool) F(receiver); }))
        {
            return cast(bool) F(receiver) ? Result.Success : processingError(param);
        }
        // void action(ref DEST receiver)
        else static if(__traits(compiles, { F(receiver); }))
        {
            F(receiver);
            return Result.Success;
        }
        // Result action(ref DEST receiver, Param!void param)
        else static if(__traits(compiles, { Result res = F(receiver, param); }))
        {
            return F(receiver, param);
        }
        // bool action(ref DEST receiver, Param!void param)
        else static if(__traits(compiles, { auto res = cast(bool) F(receiver, param); }))
        {
            return cast(bool) F(receiver, param) ? Result.Success : processingError(param);
        }
        // void action(ref DEST receiver, Param!void param)
        else static if(__traits(compiles, { F(receiver, param); }))
        {
            F(receiver, param);
            return Result.Success;
        }
        else
            static assert(false, "No-value action function has too many parameters: "~Parameters!F.stringof);
    }
}

unittest
{
    auto test(alias F, T)()
    {
        T receiver;
        assert(NoValueActionFunc!F(receiver, Param!void.init));
        return receiver;
    }
    auto testErr(alias F, T)()
    {
        T receiver;
        return NoValueActionFunc!F(receiver, Param!void.init);
    }

    // DEST action()
    assert(test!(() => 7, int) == 7);

    // Result action(ref DEST receiver)
    assert(test!((ref int r) { r=7; return Result.Success; }, int) == 7);
    assert(testErr!((ref int r) => Result.Error("error text"), int).isError("error text"));

    // bool action(ref DEST receiver)
    assert(test!((ref int p) { p=7; return true; }, int) == 7);
    assert(testErr!((ref int p) => false, int).isError("Can't process value"));

    // void action(ref DEST receiver)
    assert(test!((ref int p) { p=7; }, int) == 7);

    // Result action(ref DEST receiver, Param!void param)
    assert(test!((ref int r, Param!void p) { r=7; return Result.Success; }, int) == 7);
    assert(testErr!((ref int r, Param!void p) => Result.Error("error text"), int).isError("error text"));

    // bool action(ref DEST receiver, Param!void param)
    assert(test!((ref int r, Param!void p) { r=7; return true; }, int) == 7);
    assert(testErr!((ref int r, Param!void p) => false, int).isError("Can't process value"));

    // void action(ref DEST receiver, Param!void param)
    assert(test!((ref int r, Param!void p) { r=7; }, int) == 7);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// T parse(string[] value)
// T parse(string value)
// T parse(RawParam param)
// Result parse(ref T receiver, RawParam param)
// bool parse(ref T receiver, RawParam param)
// void parse(ref T receiver, RawParam param)
private struct ParseFunc(alias F)
{
    // T parse(string[] value)
    static if(__traits(compiles, { F(RawParam.init.value); }))
    {
        alias ReturnType = Unqual!(typeof(F(RawParam.init.value)));

        static Result opCall(ref ReturnType receiver, RawParam param)
        {
            receiver = cast(ReturnType) F(param.value);
            return Result.Success;
        }
    }
    // T parse(string value)
    else static if(__traits(compiles, { F(RawParam.init.value[0]); }))
    {
        alias ReturnType = Unqual!(typeof(F(RawParam.init.value[0])));

        static Result opCall(ref ReturnType receiver, RawParam param)
        {
            foreach (value; param.value)
                receiver = cast(ReturnType) F(value);
            return Result.Success;
        }
    }
    // T parse(RawParam param)
    else static if(__traits(compiles, { F(RawParam.init); }))
    {
        alias ReturnType = Unqual!(typeof(F(RawParam.init)));

        static Result opCall(ref ReturnType receiver, RawParam param)
        {
            receiver = cast(ReturnType) F(param);
            return Result.Success;
        }
    }
    // ... parse(..., ...)
    else static if(isCallable!F && Parameters!F.length == 2)
    {
        alias ReturnType = Parameters!F[0];

        static Result opCall(ref ReturnType receiver, RawParam param)
        {
            // Result parse(ref T receiver, RawParam param)
            static if(__traits(compiles, { Result res = F(receiver, param); }))
            {
                return F(receiver, param);
            }
            // bool parse(ref T receiver, RawParam param)
            else static if(__traits(compiles, { auto res = cast(bool) F(receiver, param); }))
            {
                return (cast(bool) F(receiver, param)) ? Result.Success : processingError(param);
            }
            // void parse(ref T receiver, RawParam param)
            else static if(__traits(compiles, { F(receiver, param); }))
            {
                F(receiver, param);
                return Result.Success;
            }
            else
                static assert(false, "Parse function is not supported");
        }
    }
    else
        static assert(false, "Parse function is not supported");
}

unittest
{
    auto test(alias F, T)(string[] values)
    {
        T receiver;
        Config config;
        assert(ParseFunc!F(receiver, RawParam(&config, "", values)));
        return receiver;
    }
    auto testErr(alias F, T)(string[] values)
    {
        T receiver;
        Config config;
        return ParseFunc!F(receiver, RawParam(&config, "", values));
    }

    // T parse(string value)
    assert(test!((string a) => a, string)(["1","2","3"]) == "3");

    // T parse(string[] value)
    assert(test!((string[] a) => a, string[])(["1","2","3"]) == ["1","2","3"]);

    // T parse(RawParam param)
    assert(test!((RawParam p) => p.value[0], string)(["1","2","3"]) == "1");

    // Result parse(ref T receiver, RawParam param)
    assert(test!((ref string[] r, RawParam p) { r = p.value; return Result.Success; }, string[])(["1","2","3"]) == ["1","2","3"]);
    assert(testErr!((ref string[] r, RawParam p) => Result.Error("error text"), string[])(["1","2","3"]).isError("error text"));

    // bool parse(ref T receiver, RawParam param)
    assert(test!((ref string[] r, RawParam p) { r = p.value; return true; }, string[])(["1","2","3"]) == ["1","2","3"]);
    assert(testErr!((ref string[] r, RawParam p) => false, string[])(["1","2","3"]).isError("Can't process value"));

    // void parse(ref T receiver, RawParam param)
    assert(test!((ref string[] r, RawParam p) { r = p.value; }, string[])(["1","2","3"]) == ["1","2","3"]);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// bool action(ref T receiver, ParseType value)
// void action(ref T receiver, ParseType value)
// Result action(ref T receiver, ParseType value)
// bool action(ref T receiver, Param!ParseType param)
// void action(ref T receiver, Param!ParseType param)
// Result action(ref T receiver, Param!ParseType param)
private struct ActionFunc(alias F)
{
    static Result opCall(T, ParseType)(ref T receiver, Param!ParseType param)
    {
        // Result action(ref T receiver, Param!ParseType param)
        static if(__traits(compiles, { Result res = F(receiver, param.value); }))
        {
            return F(receiver, param.value);
        }
        // bool action(ref T receiver, ParseType value)
        else static if(__traits(compiles, { auto res = cast(bool) F(receiver, param.value); }))
        {
            return cast(bool) F(receiver, param.value) ? Result.Success : processingError(param);
        }
        // void action(ref T receiver, ParseType value)
        else static if(__traits(compiles, { F(receiver, param.value); }))
        {
            F(receiver, param.value);
            return Result.Success;
        }
        // Result action(ref T receiver, Param!ParseType param)
        else static if(__traits(compiles, { Result res = F(receiver, param); }))
        {
            return F(receiver, param);
        }
        // bool action(ref T receiver, Param!ParseType param)
        else static if(__traits(compiles, { auto res = cast(bool) F(receiver, param); }))
        {
            return cast(bool) F(receiver, param) ? Result.Success : processingError(param);
        }
        // void action(ref T receiver, Param!ParseType param)
        else static if(__traits(compiles, { F(receiver, param); }))
        {
            F(receiver, param);
            return Result.Success;
        }
        else
            static assert(false, "Action function is not supported");
    }
}

unittest
{
    auto test(alias F, T)(T values)
    {
        T receiver;
        Config config;
        assert(ActionFunc!F(receiver, Param!T(&config, "", values)));
        return receiver;
    }
    auto testErr(alias F, T)(T values)
    {
        T receiver;
        Config config;
        return ActionFunc!F(receiver, Param!T(&config, "", values));
    }

    static assert(!__traits(compiles, { test!(() {})(["1","2","3"]); }));
    static assert(!__traits(compiles, { test!((int,int) {})(["1","2","3"]); }));

    // Result action(ref T receiver, ParseType value)
    assert(test!((ref string[] p, string[] a) { p=a; return Result.Success; })(["1","2","3"]) == ["1","2","3"]);
    assert(testErr!((ref string[] p, string[] a) => Result.Error("error text"))(["1","2","3"]).isError("error text"));

    // bool action(ref T receiver, ParseType value)
    assert(test!((ref string[] p, string[] a) { p=a; return true; })(["1","2","3"]) == ["1","2","3"]);
    assert(testErr!((ref string[] p, string[] a) => false)(["1","2","3"]).isError("Can't process value"));

    // void action(ref T receiver, ParseType value)
    assert(test!((ref string[] p, string[] a) { p=a; })(["1","2","3"]) == ["1","2","3"]);

    // Result action(ref T receiver, Param!ParseType param)
    assert(test!((ref string[] p, Param!(string[]) a) { p=a.value; return Result.Success; }) (["1","2","3"]) == ["1","2","3"]);
    assert(testErr!((ref string[] p, Param!(string[]) a) => Result.Error("error text"))(["1","2","3"]).isError("error text"));

    // bool action(ref T receiver, Param!ParseType param)
    assert(test!((ref string[] p, Param!(string[]) a) { p=a.value; return true; }) (["1","2","3"]) == ["1","2","3"]);
    assert(testErr!((ref string[] p, Param!(string[]) a) => false)(["1","2","3"]).isError("Can't process value"));

    // void action(ref T receiver, Param!ParseType param)
    assert(test!((ref string[] p, Param!(string[]) a) { p=a.value; })(["1","2","3"]) == ["1","2","3"]);
}

unittest
{
    alias test = (int[] v1, int[] v2) {
        int[] res;

        Param!(int[]) param;

        alias F = Append!(int[]);
        param.value = v1;   ActionFunc!F(res, param);

        param.value = v2;   ActionFunc!F(res, param);

        return res;
    };
    assert(test([1,2,3],[7,8,9]) == [1,2,3,7,8,9]);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private void splitValues(ref RawParam param)
{
    if(param.config.arraySep == char.init)
        return;

    import std.array : array, split;
    import std.algorithm : map, joiner;

    param.value = param.value.map!((string s) => s.split(param.config.arraySep)).joiner.array;
}

unittest
{
    alias test = (char arraySep, string[] values)
    {
        Config config;
        config.arraySep = arraySep;

        auto param = RawParam(&config, "", values);

        splitValues(param);

        return param.value;
    };

    static assert(test(',', []) == []);
    static assert(test(',', ["a","b","c"]) == ["a","b","c"]);
    static assert(test(',', ["a,b","c","d,e,f"]) == ["a","b","c","d","e","f"]);
    static assert(test(' ', ["a,b","c","d,e,f"]) == ["a,b","c","d,e,f"]);
}
