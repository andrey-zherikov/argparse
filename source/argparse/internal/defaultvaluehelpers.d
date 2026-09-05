module argparse.internal.defaultvaluehelpers;

import argparse.internal.enumhelpers: getEnumValueName;

import std.traits;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// A value that is provided as a single item in command line: it's neither an array (string is an exception
// since it's provided as is) nor an associative array
private enum isFlatValue(T) = (!isArray!T || isSomeString!T) && !isAssociativeArray!T;

// Default value can be printed only if it's possible to provide it in one command line token:
// a flat value itself, an array of flat values or an associative array with flat keys and values
private enum isSupportedDefaultValue(T) =
    isFlatValue!T ||
    (isArray!T && isFlatValue!(ForeachType!T)) ||
    (isAssociativeArray!T && isFlatValue!(KeyType!T) && isFlatValue!(ValueType!T));

unittest
{
    enum E { a, b }

    assert(isSupportedDefaultValue!int);
    assert(isSupportedDefaultValue!bool);
    assert(isSupportedDefaultValue!string);
    assert(isSupportedDefaultValue!E);
    assert(isSupportedDefaultValue!(int[]));
    assert(isSupportedDefaultValue!(int[3]));
    assert(isSupportedDefaultValue!(string[]));
    assert(isSupportedDefaultValue!(int[string]));

    // there is no way to provide these in one command line token
    assert(!isSupportedDefaultValue!(int[][]));
    assert(!isSupportedDefaultValue!(int[][string]));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Formats a value the same way as it should be provided in command line so it can be copy-pasted from help screen
private string formatDefaultValue(T)(auto ref T value)
if(isSupportedDefaultValue!T)
{
    import std.algorithm: map;
    import std.array: join;
    import std.conv: text;

    static if(is(T == enum))
        return getEnumValueName(value);
    else static if(isSomeString!T)
        return text(value);
    else static if(isAssociativeArray!T)
    {
        string[] values;

        foreach(k, v; value)
            values ~= formatDefaultValue(k) ~ "=" ~ formatDefaultValue(v);

        return values.join(",");
    }
    else static if(isArray!T)
        return value[].map!((ref _) => formatDefaultValue(_)).join(",");
    else
        return text(value);
}

unittest
{
    enum E { a, b }

    assert(formatDefaultValue(5) == "5");
    assert(formatDefaultValue(true) == "true");
    assert(formatDefaultValue("abc") == "abc");
    assert(formatDefaultValue("") == "");
    assert(formatDefaultValue(E.b) == "b");
    assert(formatDefaultValue([1,2,3]) == "1,2,3");
    assert(formatDefaultValue(cast(int[3]) [1,2,3]) == "1,2,3");
    assert(formatDefaultValue(["a","b"]) == "a,b");
    assert(formatDefaultValue([E.a,E.b]) == "a,b");
    assert(formatDefaultValue(["a": 1]) == "a=1");
    assert(formatDefaultValue(cast(int[]) []) == "");
}

unittest
{
    import argparse.internal.enumhelpers: EnumValue;

    enum E { @EnumValue(["x","y"]) a, b }

    assert(formatDefaultValue(E.a) == "x");
    assert(formatDefaultValue([E.a,E.b]) == "x,b");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Member functions (i.e. callbacks) have no default value. This check is also necessary to prevent
// `TYPE.init.symbol` from calling a member function through optional parentheses
private enum isDataMember(TYPE, string symbol) =
    !is(typeof(__traits(getMember, TYPE, symbol)) == function) &&
    !is(typeof(__traits(getMember, TYPE, symbol)) == delegate);

// Value that a member is initialized with, i.e. what a command gets if an argument is not provided in command line
private template initValueOf(TYPE, string symbol)
{
    static if(is(TYPE == class))
        enum initValueOf = __traits(getMember, new TYPE, symbol);   // TYPE.init is null for classes
    else
        enum initValueOf = __traits(getMember, TYPE.init, symbol);
}

// Text that is printed on help screen as the default value of an argument. It doesn't compile if the value can't be
// formatted in compile time, i.e. if its type is not supported (see `isSupportedDefaultValue`) or, for a struct or a
// class, if its `toString`/constructor can't be executed by CTFE
package(argparse) template defaultValueText(TYPE, string symbol)
if(isDataMember!(TYPE, symbol))
{
    enum defaultValueText = formatDefaultValue(initValueOf!(TYPE, symbol));
}

// True if a member has a default value that can be printed on help screen, i.e. it is initialized with something
// different from the init value of its type and that value can be formatted. Note that there is no way to distinguish
// `int i;` from `int i = 0;` so the latter is not considered as having a default value
package(argparse) template hasDefaultValue(TYPE, string symbol)
{
    private alias MemberType = typeof(__traits(getMember, TYPE, symbol));

    static if(isDataMember!(TYPE, symbol) &&
              __traits(compiles, { enum _ = initValueOf!(TYPE, symbol) != MemberType.init; }) &&
              __traits(compiles, defaultValueText!(TYPE, symbol)))
        enum hasDefaultValue = initValueOf!(TYPE, symbol) != MemberType.init;
    else
        enum hasDefaultValue = false;
}

unittest
{
    enum E { a, b }

    struct NoCompare { int i; @disable bool opEquals(const NoCompare) const; }
    struct NoCTFE   { int i = 1; string toString() const { assert(!__ctfe); return "rt"; } }

    struct T
    {
        string s = "abc";
        string sInit;
        E e;
        int i = 5;
        int[] a = [1,2];
        int[][] a2 = [[1,2]];
        NoCompare nc;
        NoCTFE nf = NoCTFE(2);
        void func() {}
    }

    assert( hasDefaultValue!(T, "s"));
    assert(!hasDefaultValue!(T, "sInit"));
    assert(!hasDefaultValue!(T, "e"));
    assert( hasDefaultValue!(T, "i"));
    assert( hasDefaultValue!(T, "a"));
    assert(!hasDefaultValue!(T, "nc"));
    assert(!hasDefaultValue!(T, "a2"));     // can't be formatted
    assert(!hasDefaultValue!(T, "nf"));     // can't be formatted
    assert(!hasDefaultValue!(T, "func"));

    assert(!__traits(compiles, defaultValueText!(T, "a2")));
    assert(!__traits(compiles, defaultValueText!(T, "nf")));
    assert(!__traits(compiles, defaultValueText!(T, "func")));

    assert(defaultValueText!(T, "s") == "abc");
    assert(defaultValueText!(T, "sInit") == "");
    assert(defaultValueText!(T, "e") == "a");
    assert(defaultValueText!(T, "i") == "5");
    assert(defaultValueText!(T, "a") == "1,2");

    assert(NoCTFE(1).toString == "rt");     // it's CTFE that is not supported by this type
}

unittest
{
    static class C
    {
        string s = "abc";
        int i;
    }

    assert( hasDefaultValue!(C, "s"));
    assert(!hasDefaultValue!(C, "i"));
    assert(defaultValueText!(C, "s") == "abc");

    static class NoCTFE
    {
        string s = "abc";
        this() { assert(!__ctfe); }
    }

    assert(!hasDefaultValue!(NoCTFE, "s"));
    assert(!__traits(compiles, defaultValueText!(NoCTFE, "s")));

    assert((new NoCTFE).s == "abc");        // it's CTFE that is not supported by this type
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
