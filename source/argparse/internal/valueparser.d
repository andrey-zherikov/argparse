module argparse.internal.valueparser;

import argparse.config;
import argparse.param;
import argparse.result;
import argparse.internal.errorhelpers;
import argparse.internal.enumhelpers: getEnumValues, getEnumValue;
import argparse.internal.actionfunc;
import argparse.internal.novalueactionfunc;
import argparse.internal.parsefunc;
import argparse.internal.validationfunc;

import std.traits;


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private enum void function(ref RawParam) defaultPreProcessFunc = (ref _) {};

package(argparse) enum ParsingStep
{
    preProcess, preValidate, parse, validate, action, noValueAction
}

package(argparse) struct ValueParser(PARSE, RECEIVER, PRE_VALIDATE_F, PARSE_F, VALIDATE_F, ACTION_F, NO_VALUE_ACTION_F)
{
    // We could have assigned `defaultPreProcessFunc` to `preProcess`, but we would lose `__traits(isZeroInit)`
    // and not really gain anything
    //////////////////////////
    /// pre process
    private void function(ref RawParam param) preProcess;

    auto changePreProcess(void function(ref RawParam param) func)
    {
        preProcess = func;
        return this;
    }

    //////////////////////////
    /// pre validation
    private ValidationFunc!string preValidate;

    auto changePreValidation(ValidationFunc!string func)
    {
        return ValueParser!(PARSE, RECEIVER, typeof(func), PARSE_F, VALIDATE_F, ACTION_F, NO_VALUE_ACTION_F)
            (preProcess, func, parse, validate, action, noValueAction);
    }

    //////////////////////////
    /// parse
    static if(!is(PARSE_F == byte)) // TODO: PARSE == void. 7/25/2025 8:13 PM
        private ParseFunc!PARSE parse;
    else
        private typeof(null) parse;

    auto changeParse(P)(ParseFunc!P func) const
    if(is(PARSE == void) || is(PARSE == P))
    {
        return ValueParser!(P, RECEIVER, PRE_VALIDATE_F, typeof(func), VALIDATE_F, ACTION_F, NO_VALUE_ACTION_F)
            (preProcess, preValidate, func, validate, action, noValueAction);
    }

    //////////////////////////
    /// validation
    static if(!is(VALIDATE_F == byte)) // TODO: PARSE == void. 7/25/2025 8:13 PM
        private ValidationFunc!PARSE validate;
    else
        private typeof(null) validate;

    auto changeValidation(P)(ValidationFunc!P func) const
    if(is(PARSE == void) || is(PARSE == P))
    {
        return ValueParser!(P, RECEIVER, PRE_VALIDATE_F, PARSE_F, typeof(func), ACTION_F, NO_VALUE_ACTION_F)
            (preProcess, preValidate, parse, func, action, noValueAction);
    }

    //////////////////////////
    /// action
    static if(!is(ACTION_F == byte)) // TODO: if(!is(PARSE == void) && !is(RECEIVER == void)) . 7/25/2025 8:19 PM
        private ActionFunc!(RECEIVER, PARSE) action;
    else
        private typeof(null) action;

    auto changeAction(P, R)(ActionFunc!(R, P) func) const
    if((is(PARSE == void) || is(PARSE == P)) &&
        (is(RECEIVER == void) || is(RECEIVER == R)))
    {
        return ValueParser!(P, R, PRE_VALIDATE_F, PARSE_F, VALIDATE_F, typeof(func), NO_VALUE_ACTION_F)
            (preProcess, preValidate, parse, validate, func, noValueAction);
    }


    //////////////////////////
    /// noValueAction
    static if(!is(NO_VALUE_ACTION_F == byte)) // TODO: if(!is(RECEIVER == void)). 7/25/2025 8:21 PM
        private NoValueActionFunc!RECEIVER noValueAction;
    else
        private typeof(null) noValueAction;

    auto changeNoValueAction(R)(NoValueActionFunc!R func) const
    if(is(RECEIVER == void) || is(RECEIVER == R))
    {
        return ValueParser!(PARSE, R, PRE_VALIDATE_F, PARSE_F, VALIDATE_F, ACTION_F, typeof(func))
            (preProcess, preValidate, parse, validate, action, func);
    }


    // TODO: Figure out what this thing is doing here
    alias typeDefaults = TypedValueParser;

    // TODO: We should ensure elsewhere that this substitution does not violate the type system. The compiler will catch
    // the error eventually, but if we check ourselves, we can provide far more relevant error message.
    auto change(ParsingStep step, F)(F newFunc)
    {
        // Changing a function can change our `PARSE` and/or `RECEIVER`
        static if(step == ParsingStep.preProcess)
        {
            return changePreProcess(newFunc);
        }
        else static if(step == ParsingStep.preValidate)
        {
            return changePreValidation(newFunc);
        }
        else static if(step == ParsingStep.parse)
        {
            return changeParse(newFunc);
        }
        else static if(step == ParsingStep.validate)
        {
            return changeValidation(newFunc);
        }
        else static if(step == ParsingStep.action)
        {
            return changeAction(newFunc);
        }
        else static if(step == ParsingStep.noValueAction)
        {
            return changeNoValueAction(newFunc);
        }
    }

    auto addDefaults(OTHER_PARSE, OTHER_RECEIVER, OTHER_PRE_VALIDATE_F, OTHER_PARSE_F, OTHER_VALIDATE_F, OTHER_ACTION_F, OTHER_NO_VALUE_ACTION_F)(
        ValueParser!(OTHER_PARSE, OTHER_RECEIVER, OTHER_PRE_VALIDATE_F, OTHER_PARSE_F, OTHER_VALIDATE_F, OTHER_ACTION_F, OTHER_NO_VALUE_ACTION_F) other)
    {
        static if(is(PARSE == void))
            alias PARSE = OTHER_PARSE;
        static if(is(RECEIVER == void))
            alias RECEIVER = OTHER_RECEIVER;
        static if(is(PRE_VALIDATE_F == byte)) // `byte` means "default"
        {
            alias PRE_VALIDATE_F = OTHER_PRE_VALIDATE_F;
            auto preValidate = other.preValidate;
        }
        static if(is(PARSE_F == byte))
        {
            alias PARSE_F = OTHER_PARSE_F;
            auto parse = other.parse;
        }
        static if(is(VALIDATE_F == byte))
        {
            alias VALIDATE_F = OTHER_VALIDATE_F;
            auto validate = other.validate;
        }
        static if(is(ACTION_F == byte))
        {
            alias ACTION_F = OTHER_ACTION_F;
            auto action = other.action;
        }
        static if(is(NO_VALUE_ACTION_F == byte))
        {
            alias NO_VALUE_ACTION_F = OTHER_NO_VALUE_ACTION_F;
            auto noValueAction = other.noValueAction;
        }

        return ValueParser!(PARSE, RECEIVER, PRE_VALIDATE_F, PARSE_F, VALIDATE_F, ACTION_F, NO_VALUE_ACTION_F)(
            preProcess is defaultPreProcessFunc ? other.preProcess : preProcess,
            preValidate, parse, validate, action, noValueAction
        );
    }
}

// We use `byte` as a placeholder for function types because it, unlike `void`, can be stored in a struct without
// introducing special cases (e.g., `auto f = p.validate;` just works). Yes, `ValueParser.sizeof` is then larger than
// theoretically possible (+24 bytes in the worst case), but this doesn't matter much: parsers are only used in UDAs
// so the compiler is always able to allocate memory for them statically. (Instead of `byte`, we could have chosen
// `typeof(null)`, which is more intuitive but occupies a whole machine word.)
package(argparse) enum defaultValueParser(PARSE, RECEIVER) =
    ValueParser!(PARSE, RECEIVER, byte, byte, byte, byte, byte)(defaultPreProcessFunc);

unittest
{
    auto vp = defaultValueParser!(void, void)
        .change!(ParsingStep.preValidate)(ValidationFunc!string((string s) => Result.Error("test error")))
        .change!(ParsingStep.parse)(ParseFunc!int((ref int i, RawParam p) => Result.Error("test error")));
    int receiver;
    assert(vp.preValidate(Param!string(null, "", "")).isError("test error"));
    assert(vp.parse(receiver, RawParam(null,"",[""])).isError("test error"));
}

unittest
{
    auto vp1 = defaultValueParser!(void, void)
        .change!(ParsingStep.preValidate)(ValidationFunc!string((string s) => Result.Error("a")));
    auto vp2 = defaultValueParser!(void, void)
        .change!(ParsingStep.preValidate)(ValidationFunc!string((string s) => Result.Error("b")))
        .change!(ParsingStep.validate)(ValidationFunc!int((int s) => Result.Error("c")));

    auto vp3 = vp1.addDefaults(vp2);
    assert(vp3.preValidate is vp1.preValidate);
    assert(vp3.validate is vp2.validate);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Declared as a free function to avoid instantiating it for intermediate, incompletely built parsers, which
// are not used to parse anything
package(argparse) Result parseParameter(PARSE, RECEIVER, PRE_VALIDATE_F, PARSE_F, VALIDATE_F, ACTION_F, NO_VALUE_ACTION_F)(
    ValueParser!(PARSE, RECEIVER, PRE_VALIDATE_F, PARSE_F, VALIDATE_F, ACTION_F, NO_VALUE_ACTION_F) parser,
    ref RECEIVER receiver,
    RawParam rawParam,
)
in(parser.preProcess !is null)
do
{
    if(rawParam.value.length == 0)
    {
        auto param = Param!void(rawParam.config, rawParam.name);
        static if(is(NO_VALUE_ACTION_F == byte))
            return processingError(param); // Default no-value action
        else
            return parser.noValueAction(receiver, param);
    }

    parser.preProcess(rawParam);
    Result res;

    static if(!is(PRE_VALIDATE_F == byte))
    {
        res = validateAll(parser.preValidate, rawParam); // Be careful not to use UFCS
        if(!res)
            return res;
    }

    auto parsedParam = Param!PARSE(rawParam.config, rawParam.name);

    static if(!is(PARSE_F == byte))
    {
        res = parser.parse(parsedParam.value, rawParam);
        if(!res)
            return res;
    }

    static if(!is(VALIDATE_F == byte))
    {
        res = parser.validate(parsedParam);
        if(!res)
            return res;
    }

    static if(!is(ACTION_F == byte))
    {
        res = parser.action(receiver, parsedParam);
        if(!res)
            return res;
    }
    else static if(is(RECEIVER == PARSE)) // Default action
        receiver = parsedParam.value;

    return Result.Success;
}

unittest
{
    int receiver;
    auto vp = defaultValueParser!(void, int)
        .change!(ParsingStep.preValidate)(ValidationFunc!string((string s) =>
            s.length ? Result.Success : Result.Error("prevalidation failed")
        ))
        .change!(ParsingStep.validate)(ValidationFunc!int((int x) => Result.Error("main validation failed")));
    assert(vp.parseParameter(receiver, RawParam(null,"",[""])).isError("prevalidation failed"));
    assert(vp.parseParameter(receiver, RawParam(null,"",["a"])).isError("main validation failed"));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private void preProcessBool(ref RawParam param)
{
    import std.algorithm.iteration: map;
    import std.array: array;
    import std.ascii: toLower;
    import std.string: representation;

    // convert values to lower case and replace "" with "y"
    foreach(ref value; param.value)
        value = value.length == 0 ? "y" : value.representation.map!(_ => immutable char(_.toLower)).array;
}

private template TypedValueParser(T)
if(!is(T == void))
{
    import std.conv: to;

    static if(is(T == enum))
    {
        enum TypedValueParser = defaultValueParser!(T, T)
            .change!(ParsingStep.preValidate)(ValueInList(getEnumValues!T))
            .change!(ParsingStep.parse)(ParseFunc!T((string _) => getEnumValue!T(_)));
    }
    else static if(isSomeString!T || isNumeric!T)
    {
        enum TypedValueParser = defaultValueParser!(T, T)
            .change!(ParsingStep.parse)(Convert!T);
    }
    else static if(isBoolean!T)
    {
        enum TypedValueParser = defaultValueParser!(T, T)
            .change!(ParsingStep.preProcess)(&preProcessBool)
            .change!(ParsingStep.preValidate)(ValueInList("true","yes","y","false","no","n"))
            .change!(ParsingStep.parse)(ParseFunc!T((string value)
            {
                switch(value)
                {
                    case "true", "yes", "y": return true;
                    default:                 return false;
                }
            }))
            .change!(ParsingStep.noValueAction)(SetValue(true));
    }
    else static if(isSomeChar!T)
    {
        enum TypedValueParser = defaultValueParser!(T, T)
            .change!(ParsingStep.parse)(ParseFunc!T((string value)
            {
                return value.length > 0 ? value[0].to!T : T.init;
            }));
    }
    else static if(isArray!T)
    {
        enum parseValue(TYPE) = ParseFunc!TYPE((ref TYPE receiver, RawParam param)
            {
                static if(!isStaticArray!TYPE)
                {
                    if(receiver.length < param.value.length)
                        receiver.length = param.value.length;
                }

                foreach(i, value; param.value)
                {
                    Result res = TypedValueParser!(ForeachType!TYPE).parseParameter(receiver[i], RawParam(param.config, param.name, [value]));
                    if(!res)
                        return res;
                }

                return Result.Success;
            });


        alias TElement = ForeachType!T;

        static if(!isArray!TElement || isSomeString!TElement)  // 1D array
        {
            static if(!isStaticArray!T)
                enum action = Append!T;
            else
                enum action = Assign!T;

            enum TypedValueParser = defaultValueParser!(T, T)
                .change!(ParsingStep.parse)(parseValue!T)
                .change!(ParsingStep.action)(action)
                .change!(ParsingStep.noValueAction)(NoValueActionFunc!T((ref _1, _2) => Result.Success));
        }
        else static if(!isArray!(ForeachType!TElement) || isSomeString!(ForeachType!TElement))  // 2D array
        {
            enum TypedValueParser = defaultValueParser!(TElement, T)
                .change!(ParsingStep.parse)(parseValue!TElement)
                .change!(ParsingStep.action)(Extend!T)
                .change!(ParsingStep.noValueAction)(NoValueActionFunc!T((ref T receiver, _) { receiver ~= TElement.init; return Result.Success; }));
        }
        else
            static assert(false, "Multi-dimentional arrays are not supported: " ~ T.stringof);
    }
    else static if(isAssociativeArray!T)
    {
        import std.string : indexOf;
        enum TypedValueParser = defaultValueParser!(string[], T)
            .change!(ParsingStep.parse)(PassThrough)
            .change!(ParsingStep.action)(ActionFunc!(T,string[])((ref T receiver, RawParam param)
            {
                alias K = KeyType!T;
                alias V = ValueType!T;

                foreach(input; param.value)
                {
                    auto j = indexOf(input, param.config.assignKeyValueChar);
                    if(j < 0)
                        return invalidValueError(param);

                    K key;
                    Result res = TypedValueParser!K.parseParameter(key, RawParam(param.config, param.name, [input[0 .. j]]));
                    if(!res)
                        return res;

                    V value;
                    res = TypedValueParser!V.parseParameter(value, RawParam(param.config, param.name, [input[j + 1 .. $]]));
                    if(!res)
                        return res;

                    receiver[key] = value;
                }
                return Result.Success;
            }))
            .change!(ParsingStep.noValueAction)(NoValueActionFunc!T((ref _1, _2) => Result.Success));
    }
    else static if(is(T == function) || is(T == delegate) || is(typeof(*T) == function) || is(typeof(*T) == delegate))
    {
        enum TypedValueParser = defaultValueParser!(string[], T)
            .change!(ParsingStep.parse)(PassThrough)
            .change!(ParsingStep.action)(CallFunction!T)
            .change!(ParsingStep.noValueAction)(CallFunctionNoParam!T);
    }
    else
    {
        enum TypedValueParser = defaultValueParser!(T, T)
            .change!(ParsingStep.action)(Assign!T);
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
            auto rawParam = RawParam(&config, "", [""]);
            TypedValueParser!R.parseParameter(receiver, rawParam);
        }}
}

unittest
{
    alias test(R) = (string[][] values)
    {
        Config config;
        R receiver;
        foreach(value; values)
        {
            auto rawParam = RawParam(&config, "", value);
            assert(TypedValueParser!R.parseParameter(receiver, rawParam));
        }
        return receiver;
    };

    assert(test!(string[])([["1","2","3"], [], ["4"]]) == ["1","2","3","4"]);
    assert(test!(string[][])([["1","2","3"], [], ["4"]]) == [["1","2","3"],[],["4"]]);

    assert(test!(string[string])([["a=bar","b=foo"], [], ["b=baz","c=boo"]]) == ["a":"bar", "b":"baz", "c":"boo"]);

    assert(test!(string[])([["1","2","3"], [], ["4"]]) == ["1","2","3","4"]);
    assert(test!(string[string])([["a=bar","b=foo"], [], ["b=baz","c=boo"]]) == ["a":"bar", "b":"baz", "c":"boo"]);

    assert(test!(int[])([["1","2","3"], [], ["4"]]) == [1,2,3,4]);
    assert(test!(int[][])([["1","2","3"], [], ["4"]]) == [[1,2,3],[],[4]]);

}

unittest
{
    import std.math: isNaN;
    enum MyEnum { foo, bar, }

    alias test(T) = (string[] values)
    {
        T receiver;
        Config config;
        assert(TypedValueParser!T.parseParameter(receiver, RawParam(&config, "", values)));
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
    assert(test!bool(["Yes"]) == true);
    assert(test!bool(["y"]) == true);
    assert(test!bool(["Y"]) == true);
    assert(test!bool(["true"]) == true);
    assert(test!bool(["True"]) == true);
    assert(test!bool(["no"]) == false);
    assert(test!bool(["No"]) == false);
    assert(test!bool(["n"]) == false);
    assert(test!bool(["N"]) == false);
    assert(test!bool(["false"]) == false);
    assert(test!bool(["False"]) == false);
    assert(test!MyEnum(["foo"]) == MyEnum.foo);
    assert(test!MyEnum(["bar"]) == MyEnum.bar);
    assert(test!(MyEnum[])(["bar","foo"]) == [MyEnum.bar, MyEnum.foo]);
    assert(test!(string[string])(["a=bar","b=foo"]) == ["a":"bar", "b":"foo"]);
    assert(test!(MyEnum[string])(["a=bar","b=foo"]) == ["a":MyEnum.bar, "b":MyEnum.foo]);
    assert(test!(int[MyEnum])(["bar=3","foo=5"]) == [MyEnum.bar:3, MyEnum.foo:5]);
    assert(test!(int[][])([]) == [[]]);
}

unittest
{
    alias testErr(T) = (string[] values)
    {
        T receiver;
        Config config;
        return TypedValueParser!T.parseParameter(receiver, RawParam(&config, "", values));
    };

    assert(testErr!string([]).isError("Can't process value"));
    assert(testErr!(int[])(["123","unknown"]).isError());
    assert(testErr!(bool[])(["True","unknown"]).isError());
    assert(testErr!(int[int])(["123=1","unknown"]).isError("Invalid value","unknown"));
    assert(testErr!(int[int])(["123=1","unknown=2"]).isError());
    assert(testErr!(int[int])(["123=1","2=unknown"]).isError());
}
