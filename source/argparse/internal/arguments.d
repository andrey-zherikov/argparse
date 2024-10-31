module argparse.internal.arguments;

import argparse.internal.lazystring;

import argparse.config;
import argparse.result;

import std.typecons: Nullable;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) struct ArgumentInfo
{
    string[] shortNames;
    string[] longNames;
    string[] displayNames;    // names prefixed with Config.namedArgPrefix

    string displayName() const
    {
        return displayNames[0];
    }

    LazyString description;
    string placeholder;

    string memberSymbol;

    bool hidden = false;      // if true then this argument is not printed on help page

    bool required;

    Nullable!uint position;

    bool positional() const { return !position.isNull; }

    Nullable!size_t minValuesCount;
    Nullable!size_t maxValuesCount;

    auto checkValuesCount(const Config config, string argName, size_t count) const
    {
        immutable min = minValuesCount.get;
        immutable max = maxValuesCount.get;

        // override for boolean flags
        if(isBooleanFlag && count == 1)
            return Result.Success;

        if(min == max && count != min)
            return Result.Error("Argument '",config.styling.argumentName(argName),"': expected ",min,min == 1 ? " value" : " values");

        if(count < min)
            return Result.Error("Argument '",config.styling.argumentName(argName),"': expected at least ",min,min == 1 ? " value" : " values");

        if(count > max)
            return Result.Error("Argument '",config.styling.argumentName(argName),"': expected at most ",max,max == 1 ? " value" : " values");

        return Result.Success;
    }

    bool isBooleanFlag = false;
}

unittest
{
    auto info(int min, int max)
    {
        ArgumentInfo info;
        info.minValuesCount = min;
        info.maxValuesCount = max;
        return info;
    }

    assert(info(2,4).checkValuesCount(Config.init, "", 1).isError("expected at least 2 values"));
    assert(info(2,4).checkValuesCount(Config.init, "", 2));
    assert(info(2,4).checkValuesCount(Config.init, "", 3));
    assert(info(2,4).checkValuesCount(Config.init, "", 4));
    assert(info(2,4).checkValuesCount(Config.init, "", 5).isError("expected at most 4 values"));

    assert(info(2,2).checkValuesCount(Config.init, "", 1).isError("expected 2 values"));
    assert(info(2,2).checkValuesCount(Config.init, "", 2));
    assert(info(2,2).checkValuesCount(Config.init, "", 3).isError("expected 2 values"));

    assert(info(1,1).checkValuesCount(Config.init, "", 0).isError("expected 1 value"));
    assert(info(1,1).checkValuesCount(Config.init, "", 1));
    assert(info(1,1).checkValuesCount(Config.init, "", 2).isError("expected 1 value"));

    assert(info(0,1).checkValuesCount(Config.init, "", 0));
    assert(info(0,1).checkValuesCount(Config.init, "", 1));
    assert(info(0,1).checkValuesCount(Config.init, "", 2).isError("expected at most 1 value"));

    assert(info(1,2).checkValuesCount(Config.init, "", 0).isError("expected at least 1 value"));
    assert(info(1,2).checkValuesCount(Config.init, "", 1));
    assert(info(1,2).checkValuesCount(Config.init, "", 2));
    assert(info(1,2).checkValuesCount(Config.init, "", 3).isError("expected at most 2 values"));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package ArgumentInfo finalize(MEMBERTYPE)(ArgumentInfo info, const Config config, string symbol)
{
    import std.algorithm: each, map;
    import std.array: array;
    import std.conv: text;
    import std.range: chain;
    import std.traits: isBoolean;

    info.isBooleanFlag = isBoolean!MEMBERTYPE;

    if(info.shortNames.length == 0 && info.longNames.length == 0)
    {
        if(symbol.length == 1)
            info.shortNames = [ symbol ];
        else
            info.longNames = [ symbol ];
    }

    if(info.placeholder.length == 0)
    {
        static if(is(MEMBERTYPE == enum))
        {
            import argparse.internal.enumhelpers: getEnumValues;
            import argparse.internal.utils: formatAllowedValues;

            info.placeholder = formatAllowedValues(getEnumValues!MEMBERTYPE);
        }
        else
        {
            import std.uni: toUpper;

            info.placeholder = info.positional ? symbol : symbol.toUpper;
        }
    }

    info.memberSymbol = symbol;

    if(info.positional)
        info.displayNames = [ info.placeholder ];
    else
    {
        alias toDisplayName = _ => ( _.length == 1 ? config.namedArgPrefix ~ _ : text(config.namedArgPrefix, config.namedArgPrefix, _));

        info.displayNames = chain(info.shortNames, info.longNames).map!toDisplayName.array;
    }

    if(!config.caseSensitive)
    {
        info.shortNames.each!((ref _) => _ = config.convertCase(_));
        info.longNames .each!((ref _) => _ = config.convertCase(_));
    }

    // Note: `info.{minValuesCount,maxValuesCount}` are left unchanged

    return info;
}

unittest
{
    auto createInfo(string placeholder = "")
    {
        ArgumentInfo info;
        info.position = 0;
        info.placeholder = placeholder;
        return info;
    }

    auto res = createInfo().finalize!int(Config.init, "default_name");
    assert(!res.isBooleanFlag);
    assert(res.shortNames == []);
    assert(res.longNames == ["default_name"]);
    assert(res.displayNames == ["default_name"]);
    assert(res.placeholder == "default_name");

    res = createInfo().finalize!int(Config.init, "i");
    assert(!res.isBooleanFlag);
    assert(res.shortNames == ["i"]);
    assert(res.longNames == []);
    assert(res.displayNames == ["i"]);
    assert(res.placeholder == "i");

    res = createInfo("myvalue").finalize!int(Config.init, "default_name");
    assert(res.placeholder == "myvalue");
    assert(res.displayNames == ["myvalue"]);
}

unittest
{
    auto createInfo(string placeholder = "")
    {
        ArgumentInfo info;
        info.placeholder = placeholder;
        return info;
    }

    auto res = createInfo().finalize!bool(Config.init, "default_name");
    assert(res.isBooleanFlag);
    assert(res.shortNames == []);
    assert(res.longNames == ["default_name"]);
    assert(res.displayNames == ["--default_name"]);
    assert(res.placeholder == "DEFAULT_NAME");

    res = createInfo().finalize!bool(Config.init, "b");
    assert(res.isBooleanFlag);
    assert(res.shortNames == ["b"]);
    assert(res.longNames == []);
    assert(res.displayNames == ["-b"]);
    assert(res.placeholder == "B");

    res = createInfo("myvalue").finalize!bool(Config.init, "default_name");
    assert(res.placeholder == "myvalue");
    assert(res.displayNames == ["--default_name"]);
}

unittest
{
    enum Config config = { caseSensitive: false };

    auto createInfo(string placeholder = "")
    {
        ArgumentInfo info;
        info.placeholder = placeholder;
        return info;
    }

    auto res = createInfo().finalize!bool(config, "default_name");
    assert(res.isBooleanFlag);
    assert(res.shortNames == []);
    assert(res.longNames == ["DEFAULT_NAME"]);
    assert(res.displayNames == ["--default_name"]);
    assert(res.placeholder == "DEFAULT_NAME");

    res = createInfo().finalize!bool(config, "b");
    assert(res.isBooleanFlag);
    assert(res.shortNames == ["B"]);
    assert(res.longNames == []);
    assert(res.displayNames == ["-b"]);
    assert(res.placeholder == "B");

    res = createInfo("myvalue").finalize!bool(config, "default_name");
    assert(res.placeholder == "myvalue");
    assert(res.displayNames == ["--default_name"]);
}

unittest
{
    enum E { a=1, b=1, c }

    auto createInfo(string placeholder = "")
    {
        ArgumentInfo info;
        info.placeholder = placeholder;
        return info;
    }

    auto res = createInfo().finalize!E(Config.init, "default_name");
    assert(res.placeholder == "{a,b,c}");

    res = createInfo("myvalue").finalize!E(Config.init, "default_name");
    assert(res.placeholder == "myvalue");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) struct Group
{
    string name;
    LazyString description;
    size_t[] argIndex;
}

private template getMemberGroupUDA(TYPE, string symbol)
{
    import std.traits: getUDAs;

    private enum udas = getUDAs!(__traits(getMember, TYPE, symbol), Group);

    static assert(udas.length <= 1, "Member "~TYPE.stringof~"."~symbol~" has multiple 'Group' UDAs");
    static if(udas.length > 0)
        enum getMemberGroupUDA = udas[0];
}

private enum hasMemberGroupUDA(TYPE, string symbol) = !is(typeof(getMemberGroupUDA!(TYPE, symbol)) == void);

unittest
{
    struct T
    {
        @Group("A") @Group("B")
        int incorrect;
    }

    assert(hasMemberGroupUDA!(T, "incorrect"));
    assert(!__traits(compiles, getMemberGroupUDA!(T, "incorrect")));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package struct Arguments
{
    ArgumentInfo[] info;

    // named arguments
    size_t[string] argsNamed;

    // positional arguments
    size_t[] argsPositional;

    Group[] userGroups;
    private size_t[string] groupsByName;

    private enum requiredGroupName = "Required arguments";
    private enum optionalGroupName = "Optional arguments";
    Group requiredGroup = Group(requiredGroupName);
    Group optionalGroup = Group(optionalGroupName);

    auto namedArguments() const
    {
        import std.algorithm: filter;

        return info.filter!((ref _) => !_.positional);
    }

    auto positionalArguments() const
    {
        import std.algorithm: map;

        return argsPositional.map!(ref (_) => info[_]);
    }


    void add(TYPE, ArgumentInfo[] infos)()
    {
        info = infos;

        static foreach(index, info; infos)
            add!(TYPE, info)(index);
    }

    private void add(TYPE, ArgumentInfo info)(size_t argIndex)
    {
        static if(info.memberSymbol.length > 0 && hasMemberGroupUDA!(TYPE, info.memberSymbol))
        {
            enum group = getMemberGroupUDA!(TYPE, info.memberSymbol);

            auto index = (group.name in groupsByName);
            if(index !is null)
                addArgumentImpl(userGroups[*index], info, argIndex);
            else
            {
                groupsByName[group.name] = userGroups.length;
                userGroups ~= group;
                addArgumentImpl(userGroups[$-1], info, argIndex);
            }
        }
        else static if(info.required)
            addArgumentImpl(requiredGroup, info, argIndex);
        else
            addArgumentImpl(optionalGroup, info, argIndex);
    }

    private void addArgumentImpl(ref Group group, ArgumentInfo info, size_t argIndex)
    {
        assert(info.shortNames.length + info.longNames.length > 0);

        if(info.positional)
        {
            if(argsPositional.length <= info.position.get)
                argsPositional.length = info.position.get + 1;

            argsPositional[info.position.get] = argIndex;
        }
        else
        {
            import std.range: chain;

            foreach(name; chain(info.shortNames, info.longNames))
            {
                assert(!(name in argsNamed), "Duplicated argument name: "~name);
                argsNamed[name] = argIndex;
            }
        }

        group.argIndex ~= argIndex;
    }



    struct FindResult
    {
        size_t index = size_t.max;
        const(ArgumentInfo)* arg;
    }

    FindResult findArgumentImpl(const size_t* pIndex) const
    {
        return pIndex ? FindResult(*pIndex, &info[*pIndex]) : FindResult.init;
    }

    auto findPositionalArgument(size_t position) const
    {
        return findArgumentImpl(position < argsPositional.length ? &argsPositional[position] : null);
    }

    auto findNamedArgument(string name) const
    {
        return findArgumentImpl(name in argsNamed);
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////