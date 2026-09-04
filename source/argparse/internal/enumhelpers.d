module argparse.internal.enumhelpers;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) struct EnumValue
{
    string[] values;
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private E[string] getEnumValuesMap(E)()
{
    import std.traits: EnumMembers, getUDAs;
    alias members = EnumMembers!E;

    E[string] res;
    static foreach(i, mem; members)
    {{
        enum valueUDAs = getUDAs!(mem, EnumValue);
        static assert(valueUDAs.length <= 1, E.stringof~"."~mem.stringof~" has multiple 'AllowedValues' UDAs");

        static if(valueUDAs.length > 0)
        {
            static foreach(value; valueUDAs[0].values)
                res[value] = mem;
        }
        else
            res[mem.stringof] = mem;
    }}

    return res;
}

package enum getEnumValues(E) = getEnumValuesMap!E.keys;

package E getEnumValue(E)(string value)
{
    enum values = getEnumValuesMap!E;
    return values[value];
}

// Returns the name that is used in command line for a specific enum value
package string getEnumValueName(E)(E value)
{
    import std.traits: EnumMembers, getUDAs;

    static foreach(mem; EnumMembers!E)
    {{
        enum valueUDAs = getUDAs!(mem, EnumValue);

        static if(valueUDAs.length > 0)
            enum name = valueUDAs[0].values[0];
        else
            enum name = mem.stringof;

        if(value == mem)
            return name;
    }}

    return null;
}


unittest
{
    enum E { abc, def, ghi }
    assert(getEnumValuesMap!E == ["abc":E.abc, "def":E.def, "ghi": E.ghi]);
    assert(getEnumValues!E == ["abc", "def", "ghi"]);
    assert(getEnumValue!E("abc") == E.abc);
    assert(getEnumValue!E("def") == E.def);
    assert(getEnumValue!E("ghi") == E.ghi);
    assert(getEnumValueName(E.abc) == "abc");
    assert(getEnumValueName(E.def) == "def");
    assert(getEnumValueName(E.ghi) == "ghi");
    assert(getEnumValueName(cast(E) 100) is null);
}

unittest
{
    enum E {
    @EnumValue(["a","b","c"])
        abc,
        def,
        ghi,
    }
    assert(getEnumValuesMap!E == ["a":E.abc, "b":E.abc, "c":E.abc, "def":E.def, "ghi": E.ghi]);
    assert(getEnumValues!E == ["a","b","c","def","ghi"]);
    assert(getEnumValue!E("a") == E.abc);
    assert(getEnumValue!E("b") == E.abc);
    assert(getEnumValue!E("c") == E.abc);
    assert(getEnumValue!E("def") == E.def);
    assert(getEnumValue!E("ghi") == E.ghi);
    assert(getEnumValueName(E.abc) == "a");
    assert(getEnumValueName(E.def) == "def");
    assert(getEnumValueName(E.ghi) == "ghi");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

