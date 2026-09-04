module argparse.internal.argumentudahelpers;

import argparse.api.argument: NamedArgument, PositionalArgument;
import argparse.config;
import argparse.internal.argumentuda: ArgumentUDA;
import argparse.internal.arguments: finalize;
import argparse.internal.booleanhelpers;
import argparse.internal.defaultvaluehelpers;
import argparse.param;

import std.typecons: Nullable;


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// `@NamedArgument` and `@PositionalArgument` (without parens) attach the functions as UDAs,
// but we should treat it the same as `@NamedArgument()`/`@PositionalArgument()`.
package enum isArgumentUDA(alias _ : NamedArgument) = true;
package enum isArgumentUDA(alias _ : PositionalArgument) = true;
package enum isArgumentUDA(alias uda) = is(typeof(uda) == ArgumentUDA!T, T);

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private template defaultValuesCount(T)
{
    import std.traits;

    static if(isBooleanFlag!T)
    {
        enum min = 0;
        enum max = 0;
    }
    else static if(isSomeString!T ||
                   isScalarType!T ||
                   // ... function(string value)
                   is(T == R function(string), R) ||
                   is(T == R delegate(string), R) ||
                   is(T == void function(string)) ||
                   is(T == void delegate(string)))
    {
        enum min = 1;
        enum max = 1;
    }
    else static if(isStaticArray!T)
    {
        enum min = T.length;
        enum max = T.length;
    }
    else static if(isArray!T ||
                   isAssociativeArray!T ||
                   // ... function(string[] value)
                   is(T == R function(string[]), R) ||
                   is(T == R delegate(string[]), R) ||
                   is(T == void function(string[])) ||
                   is(T == void delegate(string[])) ||
                   // ... function(RawParam value)
                   is(T == R function(RawParam), R) ||
                   is(T == R delegate(RawParam), R) ||
                   is(T == void function(RawParam)) ||
                   is(T == void delegate(RawParam)))
    {
        enum min = 1;
        enum max = size_t.max;
    }
    else
        static assert(false, "Type is not supported: " ~ T.stringof);
}

unittest
{
    struct T
    {
        bool        b;
        string      s;
        int         i;
        int[7]      sa;
        int[]       da;
        int[string] aa;
        void f();
        void fb(bool);
        void fs(string);
        void fa(string[]);
        void fp(RawParam);
        int g();
        int gs(string);
        int ga(string[]);
        int gp(RawParam);
    }
    void test(T)(size_t min, size_t max)
    {
        assert(defaultValuesCount!T.min == min);
        assert(defaultValuesCount!T.max == max);
    }
    test!(typeof(T.b))(0, 0);
    test!(typeof(T.s))(1, 1);
    test!(typeof(T.i))(1, 1);
    test!(typeof(T.sa))(7, 7);
    test!(typeof(T.da))(1, size_t.max);
    test!(typeof(T.aa))(1, size_t.max);
    test!(typeof(&T.f))(0, 0);
    test!(typeof(&T.fb))(0, 0);
    test!(typeof(&T.fs))(1, 1);
    test!(typeof(&T.fa))(1, size_t.max);
    test!(typeof(&T.fp))(1, size_t.max);
    test!(typeof(&T.g))(0, 0);
    test!(typeof(&T.gs))(1, 1);
    test!(typeof(&T.ga))(1, size_t.max);
    test!(typeof(&T.gp))(1, size_t.max);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package auto getMemberArgumentUDA(TYPE, string symbol)(const Config config)
{
    import std.meta: AliasSeq, Filter;

    alias member = __traits(getMember, TYPE, symbol);

    static if(is(typeof(member) == function) || is(typeof(member) == delegate))
        alias MemberType = typeof(&__traits(getMember, TYPE.init, symbol));
    else
        alias MemberType = typeof(member);

    alias udas = Filter!(isArgumentUDA, __traits(getAttributes, member));
    static if(__traits(compiles, __traits(getAttributes, MemberType)))
        alias typeUDAs = Filter!(isArgumentUDA, __traits(getAttributes, MemberType));
    else // On D <2.101, we are not allowed to query attributes of built-in types
        alias typeUDAs = AliasSeq!();

    static assert(udas.length <= 1, "Member "~TYPE.stringof~"."~symbol~" has multiple '*Argument' UDAs");
    static assert(typeUDAs.length <= 1, "Type "~MemberType.stringof~" has multiple '*Argument' UDAs");

    static if(udas.length > 0)
        enum memberUDA = udas[0];
    else
        enum memberUDA = NamedArgument();

    static if(typeUDAs.length > 0)
        enum initUDA = memberUDA.addDefaultUDA(typeUDAs[0]).addTypeDefaults!MemberType;
    else
        enum initUDA = memberUDA.addTypeDefaults!MemberType;

    auto result = initUDA;

    result.info = result.info.finalize!MemberType(config, symbol);

    static if(initUDA.info.minValuesCount.isNull) result.info.minValuesCount = defaultValuesCount!MemberType.min;
    static if(initUDA.info.maxValuesCount.isNull) result.info.maxValuesCount = defaultValuesCount!MemberType.max;

    // Default value is printed if it's explicitly requested or, for an optional argument, if there is something
    // meaningful to print: enum value or an initializer that differs from the init value of the member type.
    // Note that explicit request of a value that can't be formatted in compile time is a compilation error
    enum printDefaultValue = initUDA.info.printDefaultValue.get(
        !initUDA.info.required && (is(MemberType == enum) || hasDefaultValue!(TYPE, symbol)));

    static if(printDefaultValue)
    {
        static assert(__traits(compiles, defaultValueText!(TYPE, symbol)),
            "Can't get default value of "~TYPE.stringof~"."~symbol~
            ": use PrintDefaultValueInHelp with a function that returns Nullable!string");

        if(result.info.defaultValue is null)    // it's not set through PrintDefaultValueInHelp
            result.info.defaultValue = () => Nullable!string(defaultValueText!(TYPE, symbol));
    }

    return result;
}

unittest
{
    import argparse.api.argument: NumberOfValues;

    @(NamedArgument.NumberOfValues(5, 10))
    struct FiveToTen {}

    @NamedArgument
    struct UnspecifiedA {}

    struct UnspecifiedB {}

    @(NamedArgument.NumberOfValues(5, 10))
    @(NamedArgument.NumberOfValues(5, 10))
    struct Multiple {}

    struct Args
    {
        @NamedArgument bool flag;
        @NamedArgument int count;
        @NamedArgument @NamedArgument() int incorrect;

        @NamedArgument FiveToTen fiveTen;
        @NamedArgument UnspecifiedA ua;
        @NamedArgument UnspecifiedB ub;
        @NamedArgument Multiple mult;

        @(NamedArgument.NumberOfValues(1, 2)) FiveToTen fiveTen1;
        @(NamedArgument.NumberOfValues(1, 2)) UnspecifiedA ua1;
        @(NamedArgument.NumberOfValues(1, 2)) UnspecifiedB ub1;
        @(NamedArgument.NumberOfValues(1, 2)) Multiple mult1;
    }

    auto getInfo(string symbol)()
    {
        return getMemberArgumentUDA!(Args, symbol)(Config.init).info;
    }

    // Built-in types:

    auto res = getInfo!"flag";
    assert(res.minValuesCount == 0);
    assert(res.maxValuesCount == 0);

    res = getInfo!"count";
    assert(res.minValuesCount == 1);
    assert(res.maxValuesCount == 1);

    assert(!__traits(compiles, getInfo!"incorrect"));

    // With type-inherited quantifiers:

    res = getInfo!"fiveTen";
    assert(res.minValuesCount == 5);
    assert(res.maxValuesCount == 10);

    assert(!__traits(compiles, getInfo!"ua"));
    assert(!__traits(compiles, getInfo!"ub"));
    assert(!__traits(compiles, getInfo!"mult"));

    // With explicit quantifiers:

    res = getInfo!"fiveTen1";
    assert(res.minValuesCount == 1);
    assert(res.maxValuesCount == 2);

    res = getInfo!"ua1";
    assert(res.minValuesCount == 1);
    assert(res.maxValuesCount == 2);

    res = getInfo!"ub1";
    assert(res.minValuesCount == 1);
    assert(res.maxValuesCount == 2);

    assert(!__traits(compiles, getInfo!"mult1"));
}

unittest
{
    import argparse.api.argument: NamedArgument, Required, PrintDefaultValueInHelp;

    enum E { a, b }

    struct Args
    {
        string s = "abc";
        string sInit;
        E e;
        @(NamedArgument.Required) E eRequired;
        @(NamedArgument.PrintDefaultValueInHelp(false)) E eDisabled;
        @(NamedArgument.PrintDefaultValueInHelp) string forced;
        @(NamedArgument.PrintDefaultValueInHelp(() => Nullable!string("custom"))) int func;
        @(NamedArgument.PrintDefaultValueInHelp(() => Nullable!string.init)) string suppressed = "abc";
        int[] arr = [1,2];
        string[][] cantFormat = [["a"],["b"]];
        @(NamedArgument.PrintDefaultValueInHelp) string[][] cantFormatButRequested;
    }

    auto defaultValue(string symbol)()
    {
        auto get = getMemberArgumentUDA!(Args, symbol)(Config.init).info.defaultValue;
        return get is null ? Nullable!string.init : get();
    }

    assert(defaultValue!"s" == "abc");
    assert(defaultValue!"sInit".isNull);
    assert(defaultValue!"e" == "a");
    assert(defaultValue!"eRequired".isNull);
    assert(defaultValue!"eDisabled".isNull);
    assert(defaultValue!"forced" == "");
    assert(defaultValue!"func" == "custom");
    assert(defaultValue!"suppressed".isNull);
    assert(defaultValue!"arr" == "1,2");

    // there is no way to print the default value of these
    assert(defaultValue!"cantFormat".isNull);
    assert(!__traits(compiles, defaultValue!"cantFormatButRequested"));
}
