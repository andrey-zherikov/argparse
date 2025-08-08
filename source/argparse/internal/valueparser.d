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

private struct Unavailable {}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) struct ValueParser(PARSE, RECEIVER)
{
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
        preValidate = func;
        return this;
    }

    //////////////////////////
    /// parse
    static if(!is(PARSE == void))
        private ParseFunc!PARSE parse;
    else
        private Unavailable parse;

    auto changeParse(P)(ParseFunc!P func) const
    if(is(PARSE == void) || is(PARSE == P))
    {
        return ValueParser!(P, RECEIVER)( parse: func ).addDefaults(this);
    }

    //////////////////////////
    /// validation
    static if(!is(PARSE == void))
        private ValidationFunc!PARSE validate;
    else
        private Unavailable validate;

    auto changeValidation(P)(ValidationFunc!P func) const
    if(is(PARSE == void) || is(PARSE == P))
    {
        return ValueParser!(P, RECEIVER)( validate: func ).addDefaults(this);
    }

    //////////////////////////
    /// action
    static if(!is(PARSE == void) && !is(RECEIVER == void))
        private ActionFunc!(RECEIVER, PARSE) action;
    else
        private Unavailable action;

    auto changeAction(P, R)(ActionFunc!(R, P) func) const
    if((is(PARSE == void) || is(PARSE == P)) &&
        (is(RECEIVER == void) || is(RECEIVER == R)))
    {
        return ValueParser!(P, R)( action: func ).addDefaults(this);
    }

    //////////////////////////
    /// noValueAction
    static if(!is(RECEIVER == void))
        private NoValueActionFunc!RECEIVER noValueAction;
    else
        private Unavailable noValueAction;

    auto changeNoValueAction(R)(NoValueActionFunc!R func) const
    if(is(RECEIVER == void) || is(RECEIVER == R))
    {
        return ValueParser!(PARSE, R)( noValueAction: func ).addDefaults(this);
    }


    auto addDefaults(OTHER_PARSE, OTHER_RECEIVER)(ValueParser!(OTHER_PARSE, OTHER_RECEIVER) other)
    {
        static if(is(PARSE == void))
            alias PARSE = OTHER_PARSE;
        static if(is(RECEIVER == void))
            alias RECEIVER = OTHER_RECEIVER;

        auto vp = ValueParser!(PARSE, RECEIVER)(
            preProcess ? preProcess : other.preProcess,
            preValidate ? preValidate : other.preValidate);

        auto choose(LHS, RHS)(RHS rhs, LHS lhs)
        {
            static if(is(RHS == Unavailable))
                return lhs;
            else static if(is(RHS == LHS))
                return rhs ? rhs : lhs;
            else
                return rhs;
        }

        vp.parse         = choose(parse,         other.parse);
        vp.validate      = choose(validate,      other.validate);
        vp.action        = choose(action,        other.action);
        vp.noValueAction = choose(noValueAction, other.noValueAction);

        return vp;
    }

    auto addTypeDefaults(TYPE)()
    {
        return addDefaults(TypedValueParser!TYPE);
    }
}

unittest
{
    auto vp = ValueParser!(void, void).init
        .changePreValidation(ValidationFunc!string((string s) => Result.Error("test error")))
        .changeParse(ParseFunc!int((ref int i, RawParam p) => Result.Error("test error")));
    int receiver;
    assert(vp.preValidate(Param!string(null, "", "")).isError("test error"));
    assert(vp.parse(receiver, RawParam(null,"",[""])).isError("test error"));
}

unittest
{
    auto vp1 = ValueParser!(void, void).init
        .changePreValidation(ValidationFunc!string((string s) => Result.Error("a")));
    auto vp2 = ValueParser!(void, void).init
        .changePreValidation(ValidationFunc!string((string s) => Result.Error("b")))
        .changeValidation(ValidationFunc!int((int s) => Result.Error("c")));

    auto vp3 = vp1.addDefaults(vp2);
    assert(vp3.preValidate is vp1.preValidate);
    assert(vp3.validate is vp2.validate);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Declared as a free function to avoid instantiating it for intermediate, incompletely built parsers, which
// are not used to parse anything
//
// Procedure to process (parse) the values to an argument of type RECEIVER
//  - if there is a value(s):
//      - pre validate raw strings
//      - parse raw strings
//      - validate parsed values
//      - action with values
//  - if there is no value:
//      - action if no value
// Requirement: rawValues.length must be correct
package(argparse) Result parseParameter(PARSE, RECEIVER)(ValueParser!(PARSE, RECEIVER) parser, ref RECEIVER receiver, RawParam rawParam)
if(!is(PARSE == void) && !is(RECEIVER == void))
{
    if(rawParam.value.length == 0)
    {
        auto param = Param!void(rawParam.config, rawParam.name);
        if(parser.noValueAction)
            return parser.noValueAction(receiver, param);
        else
            return processingError(param); // Default no-value action
    }

    if(parser.preProcess)
        parser.preProcess(rawParam);

    Result res;

    if(parser.preValidate)
    {
        res = parser.preValidate(rawParam);
        if(!res)
            return res;
    }

    auto parsedParam = Param!PARSE(rawParam.config, rawParam.name);

    assert(parser.parse);
    res = parser.parse(parsedParam.value, rawParam);
    if(!res)
        return res;

    if(parser.validate)
    {
        res = parser.validate(parsedParam);
        if(!res)
            return res;
    }

    assert(parser.action);
    res = parser.action(receiver, parsedParam);
    if(!res)
        return res;

    return Result.Success;
}

unittest
{
    string receiver;
    auto vp = ValueParser!(void, string).init
        .changePreValidation(ValidationFunc!string((string s) =>
            s.length ? Result.Success : Result.Error("prevalidation failed")
        ))
        .changeParse(ParseFunc!string(_ => _))
        .changeValidation(ValidationFunc!string((string _) => Result.Error("main validation failed")));
    assert(vp.parseParameter(receiver, RawParam(null,"",[""])).isError("prevalidation failed"));
    assert(vp.parseParameter(receiver, RawParam(null,"",["a"])).isError("main validation failed"));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private template TypedValueParser(T)
if(!is(T == void))
{
    import std.conv: to;

    static if(is(T == enum))
    {
        enum TypedValueParser = ValueParser!(T, T).init
            .changePreValidation(ValueInList(getEnumValues!T))
            .changeParse(ParseFunc!T((string _) => getEnumValue!T(_)))
            .changeAction(Assign!T);
    }
    else static if(isSomeString!T || isNumeric!T)
    {
        enum TypedValueParser = ValueParser!(T, T).init
            .changeParse(Convert!T)
            .changeAction(Assign!T);
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
            .changePreValidation(ValueInList("true","yes","y","false","no","n"))
            .changeParse(ParseFunc!T((string value)
            {
                switch(value)
                {
                    case "true", "yes", "y": return true;
                    default:                 return false;
                }
            }))
            .changeAction(Assign!T)
            .changeNoValueAction(SetValue(true));
    }
    else static if(isSomeChar!T)
    {
        enum TypedValueParser = ValueParser!(T, T).init
            .changeParse(ParseFunc!T((string value)
            {
                return value.length > 0 ? value[0].to!T : T.init;
            }))
            .changeAction(Assign!T);
    }
    else static if(isArray!T)
    {
        enum parseValue(TYPE) = ParseFunc!TYPE((ref TYPE receiver, RawParam param)
            {
                import std.array: split;

                auto values = param.value.length == 1 && !param.config.variadicNamedArgument ?
                              param.value[0].split(param.config.valueSep) :
                              param.value;

                static if(!isStaticArray!TYPE)
                {
                    if(receiver.length < values.length)
                        receiver.length = values.length;
                }

                foreach(i, value; values)
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
                .changeNoValueAction(NoValueActionFunc!T((ref _1, _2) => Result.Success));
        }
        else static if(!isArray!(ForeachType!TElement) || isSomeString!(ForeachType!TElement))  // 2D array
        {
            enum TypedValueParser = ValueParser!(TElement, T).init
                .changeParse(parseValue!TElement)
                .changeAction(Extend!T)
                .changeNoValueAction(NoValueActionFunc!T((ref T receiver, _) { receiver ~= TElement.init; return Result.Success; }));
        }
        else
            static assert(false, "Multi-dimentional arrays are not supported: " ~ T.stringof);
    }
    else static if(isAssociativeArray!T)
    {
        import std.array: split;
        import std.string : indexOf;

        enum TypedValueParser = ValueParser!(string[], T).init
            .changeParse(ParseFunc!(string[])((string[] _) => _))
            .changeAction(ActionFunc!(T,string[])((ref T receiver, RawParam param)
            {
                alias K = KeyType!T;
                alias V = ValueType!T;

                foreach(paramValue; param.value)
                    foreach(input; paramValue.split(param.config.valueSep))
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
            .changeNoValueAction(NoValueActionFunc!T((ref _1, _2) => Result.Success));
    }
    else static if(is(T == function) || is(T == delegate) || is(typeof(*T) == function) || is(typeof(*T) == delegate))
    {
        enum TypedValueParser = ValueParser!(string[], T).init
            .changeParse(ParseFunc!(string[])((string[] _) => _))
            .changeAction(ActionFunc!(T,string[])((ref T receiver, RawParam param)
            {
                auto parseInto(DEST)(ref DEST dest)
                {
                    return TypedValueParser!DEST.parseParameter(dest, param);
                }

                // Result function()
                static if(is(T == Result function()) || is(T == Result delegate()))
                {
                    return receiver();
                }
                // void function()
                else static if(is(T == void function()) || is(T == void delegate()))
                {
                    receiver();
                    return Result.Success;
                }
                // Result function(string value)
                else static if(is(T == Result function(string)) || is(T == Result delegate(string)))
                {
                    foreach(value; param.value)
                    {
                        auto res = receiver(value);
                        if(!res)
                            return res;
                    }
                    return Result.Success;
                }
                // void function(string value)
                else static if(is(T == void function(string)) || is(T == void delegate(string)))
                {
                    foreach(value; param.value)
                        receiver(value);

                    return Result.Success;
                }
                // Result function(string[] value)
                else static if(is(T == Result function(string[])) || is(T == Result delegate(string[])))
                {
                    string[] value;
                    Result res = TypedValueParser!(string[]).parseParameter(value, param);
                    if(!res)
                        return res;

                    return receiver(value);
                }
                // void function(string[] value)
                else static if(is(T == void function(string[])) || is(T == void delegate(string[])))
                {
                    string[] value;
                    Result res = TypedValueParser!(string[]).parseParameter(value, param);
                    if(!res)
                        return res;

                    receiver(value);
                    return Result.Success;
                }
                // Result function(RawParam value)
                else static if(is(T == Result function(RawParam)) || is(T == Result delegate(RawParam)))
                {
                    return receiver(param);
                }
                // void function(RawParam value)
                else static if(is(T == void function(RawParam)) || is(T == void delegate(RawParam)))
                {
                    receiver(param);
                    return Result.Success;
                }
                else
                    static assert(false, "Unsupported callback: " ~ T.stringof);

                return Result.Success;
            }))
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
    struct T
    {
        int a_;
        string[] b_;
        string[][] c_;
        string[][] d_;

        void av() { a_++; }
        void bv(string s) { b_ ~= s; }
        void cv(string[] s) { c_ ~= s; }
        void dv(RawParam p) { d_ ~= p.value; }

        Result as() { a_++; return Result.Success; }
        Result bs(string s) { b_ ~= s; return Result.Success; }
        Result cs(string[] s) { c_ ~= s; return Result.Success; }
        Result ds(RawParam p) { d_ ~= p.value; return Result.Success; }

        Result ae() { return Result.Error("my error"); }
        Result be(string s) { return Result.Error("my error"); }
        Result ce(string[] s) { return Result.Error("my error"); }
        Result de(RawParam p) { return Result.Error("my error"); }
    }

    auto test(F)(string[] values, F func)
    {
        Config config;
        return TypedValueParser!F.parseParameter(func, RawParam(&config, "", values));
    }

    {
        T t;
        assert(test(["a"], &t.av));
        assert(t.a_ == 1);
        assert(test(["a"], &t.as));
        assert(t.a_ == 2);
        assert(test(["a"], &t.ae).isError("my error"));
    }
    {
        T t;
        assert(test(["a","b","c"], &t.bv));
        assert(t.b_ == ["a","b","c"]);
        assert(test(["d","e","f"], &t.bs));
        assert(t.b_ == ["a","b","c","d","e","f"]);
        assert(test(["a"], &t.be).isError("my error"));
    }
    {
        T t;
        assert(test(["a","b","c"], &t.cv));
        assert(t.c_ == [["a","b","c"]]);
        assert(test(["d","e","f"], &t.cs));
        assert(t.c_ == [["a","b","c"],["d","e","f"]]);
        assert(test(["a"], &t.ce).isError("my error"));
    }
    {
        T t;
        assert(test(["a,b,c"], &t.cv));
        assert(t.c_ == [["a","b","c"]]);
        assert(test(["d,e,f"], &t.cs));
        assert(t.c_ == [["a","b","c"],["d","e","f"]]);
    }
    {
        T t;
        assert(test(["a","b","c"], &t.dv));
        assert(t.d_ == [["a","b","c"]]);
        assert(test(["d","e","f"], &t.ds));
        assert(t.d_ == [["a","b","c"],["d","e","f"]]);
        assert(test(["a"], &t.de).isError("my error"));
    }
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
