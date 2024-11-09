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

package(argparse) struct ValueParser(PARSE_TYPE, RECEIVER_TYPE)
{
    //////////////////////////
    /// pre process
    void function(ref RawParam param) preProcess;

    auto changePreProcess(void function(ref RawParam param) func)
    {
        preProcess = func;
        return this;
    }

    //////////////////////////
    /// pre validation
    ValidationFunc!(string[]) preValidate;

    auto changePreValidation(ValidationFunc!(string[]) func)
    {
        preValidate = func;
        return this;
    }

    //////////////////////////
    /// parse
    static if(!is(PARSE_TYPE == void))
        ParseFunc!PARSE_TYPE parse;

    auto changeParse(P)(ParseFunc!P func) const
    if(is(PARSE_TYPE == void) || is(PARSE_TYPE == P))
    {
        return ValueParser!(P, RECEIVER_TYPE)( parse: func ).addDefaults(this);
    }

    //////////////////////////
    /// validation
    static if(!is(PARSE_TYPE == void))
        ValidationFunc!PARSE_TYPE validate;

    auto changeValidation(P)(ValidationFunc!P func) const
    if(is(PARSE_TYPE == void) || is(PARSE_TYPE == P))
    {
        return ValueParser!(P, RECEIVER_TYPE)( validate: func ).addDefaults(this);
    }

    //////////////////////////
    /// action
    static if(!is(PARSE_TYPE == void) && !is(RECEIVER_TYPE == void))
        ActionFunc!(RECEIVER_TYPE, PARSE_TYPE) action;

    auto changeAction(P, R)(ActionFunc!(R, P) func) const
    if((is(PARSE_TYPE == void) || is(PARSE_TYPE == P)) &&
        (is(RECEIVER_TYPE == void) || is(RECEIVER_TYPE == R)))
    {
        return ValueParser!(P, R)( action: func ).addDefaults(this);
    }

    //////////////////////////
    /// noValueAction
    static if(!is(RECEIVER_TYPE == void))
        NoValueActionFunc!RECEIVER_TYPE noValueAction;

    auto changeNoValueAction(R)(NoValueActionFunc!R func) const
    if(is(RECEIVER_TYPE == void) || is(RECEIVER_TYPE == R))
    {
        return ValueParser!(PARSE_TYPE, R)( noValueAction: func ).addDefaults(this);
    }

    //////////////////////////
    auto addDefaults(P, R)(ValueParser!(P, R) other) const
    {
        static if(is(PARSE_TYPE == void))
            alias RES_P = P;
        else
            alias RES_P = PARSE_TYPE;

        static if(is(RECEIVER_TYPE == void))
            alias RES_R = R;
        else
            alias RES_R = RECEIVER_TYPE;

        ValueParser!(RES_P, RES_R) res;
        res.preProcess = preProcess ? preProcess : other.preProcess;
        res.preValidate = preValidate ? preValidate : other.preValidate;

        static if(!is(PARSE_TYPE == void))
        {
            res.parse = parse;
            res.validate = validate;
        }

        static if(!is(PARSE_TYPE == void) && !is(RECEIVER_TYPE == void))
            res.action = action;

        static if(!is(RECEIVER_TYPE == void))
            res.noValueAction = noValueAction;

        static if(!is(RES_P == void) && is(RES_P == P))
        {
            if(!res.parse)
                res.parse = other.parse;
            if(!res.validate)
                res.validate = other.validate;
        }

        static if(!is(RES_P == void) && !is(RES_R == void))
        {
            static if(is(RES_P == P) && is(RES_R == R))
                if(!res.action)
                    res.action = other.action;
        }

        static if(!is(RES_R == void) && is(RES_R == R))
        {
            if(!res.noValueAction)
                res.noValueAction = other.noValueAction;
        }

        return res;
    }

    auto addTypeDefaults(TYPE)()
    {
        static if(!is(typeof(TypedValueParser!TYPE) == void))
            return addDefaults(TypedValueParser!TYPE);
        else
            return this;
    }

    // Procedure to process (parse) the values to an argument of type RECEIVER
    //  - if there is a value(s):
    //      - pre validate raw strings
    //      - parse raw strings
    //      - validate parsed values
    //      - action with values
    //  - if there is no value:
    //      - action if no value
    // Requirement: rawValues.length must be correct
    Result parseParameter(RECEIVER)(ref RECEIVER receiver, RawParam param)
    {
        static assert(!is(PARSE_TYPE == void) && !is(RECEIVER_TYPE == void));
        return addTypeDefaults!RECEIVER.addDefaults.parseImpl(receiver, param);
    }

    static if(!is(PARSE_TYPE == void) && !is(RECEIVER_TYPE == void))
    {
        auto addDefaults()
        {
            if(!preProcess)
                preProcess = (ref _) {};
            if(!preValidate)
                preValidate = (string[] _) => true;
            if(!validate)
                validate = (PARSE_TYPE _) => true;
            static if(__traits(compiles, { RECEIVER_TYPE receiver; receiver = PARSE_TYPE.init; }))
            {
                if (!action)
                    action = (ref RECEIVER_TYPE receiver, Param!PARSE_TYPE param) { receiver = param.value; };
            }
            if(!noValueAction)
                noValueAction = (ref RECEIVER_TYPE _, param) => processingError(param);

            return this;
        }


        Result parseImpl(RECEIVER_TYPE* receiver, ref RawParam rawParam) const
        {
            return parseImpl(*receiver, rawParam);
        }
        Result parseImpl(ref RECEIVER_TYPE receiver, ref RawParam rawParam) const
        {
            assert(preProcess);
            assert(preValidate);
            assert(parse);
            assert(validate);
            assert(action);
            assert(noValueAction);

            if (rawParam.value.length == 0)
            {
                return noValueAction(receiver, Param!void(rawParam.config, rawParam.name));
            }
            else
            {
                preProcess(rawParam);

                Result res = preValidate(rawParam);
                if (!res)
                    return res;

                auto parsedParam = Param!PARSE_TYPE(rawParam.config, rawParam.name);

                res = parse(parsedParam.value, rawParam);
                if (!res)
                    return res;

                res = validate(parsedParam);
                if (!res)
                    return res;

                res = action(receiver, parsedParam);
                if (!res)
                    return res;

                return Result.Success;
            }
        }
    }
}


unittest
{
    int receiver;
    auto vp = ValueParser!(void, void)()
        .changeParse(ParseFunc!int((ref int i, RawParam p) => Result.Error("test error")));
    assert(vp.parse(receiver, RawParam(null,"",[""])).isError("test error"));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private template TypedValueParser(T)
if(!is(T == void))
{
    import std.conv: to;

    static if(is(T == enum))
    {
        enum TypedValueParser = ValueParser!(T, T).init
            .changePreValidation(ValidationFunc!(string[])((RawParam _) => ValueInList(getEnumValues!T)(_)))
            .changeParse(ParseFunc!T((string _) => getEnumValue!T(_)));
    }
    else static if(isSomeString!T || isNumeric!T)
    {
        enum TypedValueParser = ValueParser!(T, T).init
            .changeParse(Convert!T);
    }
    else static if(isBoolean!T)
    {
        enum TypedValueParser = ValueParser!(T, T).init
            .changePreProcess((ref RawParam param)
            {
                import std.algorithm.iteration: map;
                import std.array: array;
                import std.ascii: toLower;
                import std.string: representation;

                // convert values to lower case and replace "" with "y"
                foreach(ref value; param.value)
                    value = value.length == 0 ? "y" : value.representation.map!(_ => immutable char(_.toLower)).array;
            })
            .changePreValidation(ValidationFunc!(string[])((RawParam _) => ValueInList("true","yes","y","false","no","n")(_)))
            .changeParse(ParseFunc!T((string value)
            {
                switch(value)
                {
                    case "true", "yes", "y": return true;
                    default:                 return false;
                }
            }))
            .changeNoValueAction(NoValueActionFunc!T((ref T receiver) { receiver = true; }));
    }
    else static if(isSomeChar!T)
    {
        enum TypedValueParser = ValueParser!(T, T).init
            .changeParse(ParseFunc!T((string value)
            {
                import std.conv: to;
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

            enum TypedValueParser = ValueParser!(T, T).init
                .changeParse(parseValue!T)
                .changeAction(action)
                .changeNoValueAction(NoValueActionFunc!T((ref T receiver) => Result.Success));
        }
        else static if(!isArray!(ForeachType!TElement) || isSomeString!(ForeachType!TElement))  // 2D array
        {
            enum TypedValueParser = ValueParser!(TElement, T).init
                .changeParse(parseValue!TElement)
                .changeAction(Extend!T)
                .changeNoValueAction(NoValueActionFunc!T((ref T receiver) { receiver ~= TElement.init; }));
        }
        else
            static assert(false, "Multi-dimentional arrays are not supported: " ~ T.stringof);
    }
    else static if(isAssociativeArray!T)
    {
        import std.string : indexOf;
        enum TypedValueParser = ValueParser!(string[], T).init
            .changeParse(PassThrough)
            .changeAction(ActionFunc!(T,string[])((ref T receiver, RawParam param)
            {
                alias K = KeyType!T;
                alias V = ValueType!T;

                foreach(input; param.value)
                {
                    auto j = indexOf(input, param.config.assignChar);
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
            .changeNoValueAction(NoValueActionFunc!T((ref T receiver) => Result.Success));
    }
    else static if(is(T == function) || is(T == delegate) || is(typeof(*T) == function) || is(typeof(*T) == delegate))
    {
        enum TypedValueParser = ValueParser!(string[], T).init
            .changeParse(PassThrough)
            .changeAction(CallFunction!T)
            .changeNoValueAction(CallFunctionNoParam!T);
    }
    else
    {
        enum TypedValueParser = ValueParser!(T, T).init
            .changeAction(Assign!T);
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
