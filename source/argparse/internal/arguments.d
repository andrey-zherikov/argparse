module argparse.internal.arguments;

import argparse.internal.lazystring;

import argparse.config;
import argparse.result;

import std.typecons: Nullable;
import std.traits: getUDAs;

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

    bool hideFromHelp = false;      // if true then this argument is not printed on help page

    bool required;

    Nullable!uint position;

    bool positional() const { return !position.isNull; }

    Nullable!ulong minValuesCount;
    Nullable!ulong maxValuesCount;

    auto checkValuesCount(Config config)(string argName, ulong count) const
    {
        immutable min = minValuesCount.get;
        immutable max = maxValuesCount.get;

        // override for boolean flags
        if(allowBooleanNegation && count == 1)
            return Result.Success;

        if(min == max && count != min)
            return Result.Error("Argument '",config.styling.argumentName(argName),"': expected ",min,min == 1 ? " value" : " values");

        if(count < min)
            return Result.Error("Argument '",config.styling.argumentName(argName),"': expected at least ",min,min == 1 ? " value" : " values");

        if(count > max)
            return Result.Error("Argument '",config.styling.argumentName(argName),"': expected at most ",max,max == 1 ? " value" : " values");

        return Result.Success;
    }

    bool allowBooleanNegation = true;
    bool ignoreInDefaultCommand;
}

unittest
{
    auto info(int min, int max)
    {
        ArgumentInfo info;
        info.allowBooleanNegation = false;
        info.minValuesCount = min;
        info.maxValuesCount = max;
        return info;
    }

    assert(info(2,4).checkValuesCount!(Config.init)("", 1).isError("expected at least 2 values"));
    assert(info(2,4).checkValuesCount!(Config.init)("", 2));
    assert(info(2,4).checkValuesCount!(Config.init)("", 3));
    assert(info(2,4).checkValuesCount!(Config.init)("", 4));
    assert(info(2,4).checkValuesCount!(Config.init)("", 5).isError("expected at most 4 values"));

    assert(info(2,2).checkValuesCount!(Config.init)("", 1).isError("expected 2 values"));
    assert(info(2,2).checkValuesCount!(Config.init)("", 2));
    assert(info(2,2).checkValuesCount!(Config.init)("", 3).isError("expected 2 values"));

    assert(info(1,1).checkValuesCount!(Config.init)("", 0).isError("expected 1 value"));
    assert(info(1,1).checkValuesCount!(Config.init)("", 1));
    assert(info(1,1).checkValuesCount!(Config.init)("", 2).isError("expected 1 value"));

    assert(info(0,1).checkValuesCount!(Config.init)("", 0));
    assert(info(0,1).checkValuesCount!(Config.init)("", 1));
    assert(info(0,1).checkValuesCount!(Config.init)("", 2).isError("expected at most 1 value"));

    assert(info(1,2).checkValuesCount!(Config.init)("", 0).isError("expected at least 1 value"));
    assert(info(1,2).checkValuesCount!(Config.init)("", 1));
    assert(info(1,2).checkValuesCount!(Config.init)("", 2));
    assert(info(1,2).checkValuesCount!(Config.init)("", 3).isError("expected at most 2 values"));
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
    private enum udas = getUDAs!(__traits(getMember, TYPE, symbol), Group);

    static assert(udas.length <= 1, "Member "~TYPE.stringof~"."~symbol~" has multiple 'Group' UDAs");
    static if(udas.length > 0)
        enum getMemberGroupUDA = udas[0];
}

private enum hasMemberGroupUDA(TYPE, alias symbol) = __traits(compiles, { enum group = getMemberGroupUDA!(TYPE, symbol); });


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
            add!(TYPE, info, index);
    }

    private void add(TYPE, ArgumentInfo info, size_t argIndex)()
    {
        alias addArgument = addArgumentImpl!(TYPE, info, argIndex);

        static if(hasMemberGroupUDA!(TYPE, info.memberSymbol))
        {
            enum group = getMemberGroupUDA!(TYPE, info.memberSymbol);

            auto index = (group.name in groupsByName);
            if(index !is null)
                addArgument(userGroups[*index]);
            else
            {
                groupsByName[group.name] = userGroups.length;
                userGroups ~= group;
                addArgument(userGroups[$-1]);
            }
        }
        else static if(info.required)
            addArgument(requiredGroup);
        else
            addArgument(optionalGroup);
    }

    private void addArgumentImpl(TYPE, ArgumentInfo info, size_t argIndex)(ref Group group)
    {
        static assert(info.shortNames.length + info.longNames.length > 0);

        static if(info.positional)
        {
            if(argsPositional.length <= info.position.get)
                argsPositional.length = info.position.get + 1;

            argsPositional[info.position.get] = argIndex;
        }
        else
        {
            import std.range: chain;

            static foreach(name; chain(info.shortNames, info.longNames))
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