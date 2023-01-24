module argparse.internal.arguments;

import argparse.internal.utils: partiallyApply;
import argparse.internal.lazystring;

import argparse.config;
import argparse.result;

import std.typecons: Nullable;
import std.traits: getUDAs;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) struct ArgumentInfo
{
    string[] names;
    string[] displayNames;    // names prefixed with Config.namedArgChar

    string displayName() const
    {
        return displayNames[0];
    }

    LazyString description;
    string placeholder;

    bool hideFromHelp = false;      // if true then this argument is not printed on help page

    bool required;

    Nullable!uint position;

    bool positional() const { return !position.isNull; }

    Nullable!ulong minValuesCount;
    Nullable!ulong maxValuesCount;

    auto checkValuesCount(string argName, ulong count) const
    {
        immutable min = minValuesCount.get;
        immutable max = maxValuesCount.get;

        // override for boolean flags
        if(allowBooleanNegation && count == 1)
            return Result.Success;

        if(min == max && count != min)
        {
            return Result.Error("argument ",argName,": expected ",min,min == 1 ? " value" : " values");
        }
        if(count < min)
        {
            return Result.Error("argument ",argName,": expected at least ",min,min == 1 ? " value" : " values");
        }
        if(count > max)
        {
            return Result.Error("argument ",argName,": expected at most ",max,max == 1 ? " value" : " values");
        }

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

    assert(info(2,4).checkValuesCount("", 1).isError("expected at least 2 values"));
    assert(info(2,4).checkValuesCount("", 2));
    assert(info(2,4).checkValuesCount("", 3));
    assert(info(2,4).checkValuesCount("", 4));
    assert(info(2,4).checkValuesCount("", 5).isError("expected at most 4 values"));

    assert(info(2,2).checkValuesCount("", 1).isError("expected 2 values"));
    assert(info(2,2).checkValuesCount("", 2));
    assert(info(2,2).checkValuesCount("", 3).isError("expected 2 values"));

    assert(info(1,1).checkValuesCount("", 0).isError("expected 1 value"));
    assert(info(1,1).checkValuesCount("", 1));
    assert(info(1,1).checkValuesCount("", 2).isError("expected 1 value"));

    assert(info(0,1).checkValuesCount("", 0));
    assert(info(0,1).checkValuesCount("", 1));
    assert(info(0,1).checkValuesCount("", 2).isError("expected at most 1 value"));

    assert(info(1,2).checkValuesCount("", 0).isError("expected at least 1 value"));
    assert(info(1,2).checkValuesCount("", 1));
    assert(info(1,2).checkValuesCount("", 2));
    assert(info(1,2).checkValuesCount("", 3).isError("expected at most 2 values"));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package alias Restriction = Result delegate(Config* config, in bool[size_t] cliArgs, in ArgumentInfo[] allArgs);

package struct Restrictions
{
    static Restriction RequiredArg(ArgumentInfo info)(size_t index)
    {
        return partiallyApply!((size_t index, Config* config, in bool[size_t] cliArgs, in ArgumentInfo[] allArgs)
        {
            return (index in cliArgs) ?
                Result.Success :
                Result.Error("The following argument is required: ", info.displayName);
        })(index);
    }

    static Result RequiredTogether(Config* config,
                                   in bool[size_t] cliArgs,
                                   in ArgumentInfo[] allArgs,
                                   in size_t[] restrictionArgs)
    {
        size_t foundIndex = size_t.max;
        size_t missedIndex = size_t.max;

        foreach(index; restrictionArgs)
        {
            if(index in cliArgs)
            {
                if(foundIndex == size_t.max)
                    foundIndex = index;
            }
            else if(missedIndex == size_t.max)
                missedIndex = index;

            if(foundIndex != size_t.max && missedIndex != size_t.max)
                return Result.Error("Missed argument '", allArgs[missedIndex].displayName, "' - it is required by argument '", allArgs[foundIndex].displayName);
        }

        return Result.Success;
    }

    static Result MutuallyExclusive(Config* config,
                                    in bool[size_t] cliArgs,
                                    in ArgumentInfo[] allArgs,
                                    in size_t[] restrictionArgs)
    {
        size_t foundIndex = size_t.max;

        foreach(index; restrictionArgs)
            if(index in cliArgs)
            {
                if(foundIndex == size_t.max)
                    foundIndex = index;
                else
                    return Result.Error("Argument '", allArgs[foundIndex].displayName, "' is not allowed with argument '", allArgs[index].displayName,"'");
            }

        return Result.Success;
    }

    static Result RequiredAnyOf(Config* config,
                                in bool[size_t] cliArgs,
                                in ArgumentInfo[] allArgs,
                                in size_t[] restrictionArgs)
    {
        import std.algorithm: map;
        import std.array: join;

        foreach(index; restrictionArgs)
            if(index in cliArgs)
                return Result.Success;

        return Result.Error("One of the following arguments is required: '", restrictionArgs.map!(_ => allArgs[_].displayName).join("', '"), "'");
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) struct Group
{
    string name;
    LazyString description;
    size_t[] arguments;
}

private template getMemberGroupUDA(TYPE, alias symbol)
{
    private enum udas = getUDAs!(__traits(getMember, TYPE, symbol), Group);

    static assert(udas.length <= 1, "Member "~TYPE.stringof~"."~symbol~" has multiple 'Group' UDAs");
    static if(udas.length > 0)
        enum getMemberGroupUDA = udas[0];
}

private enum hasMemberGroupUDA(TYPE, alias symbol) = __traits(compiles, { enum group = getMemberGroupUDA!(TYPE, symbol); });


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) struct RestrictionGroup
{
    string location;

    enum Type { together, exclusive }
    Type type;

    size_t[] arguments;

    bool required;
}

unittest
{
    assert(!RestrictionGroup.init.required);
}

private auto getRestrictionGroups(TYPE, alias symbol)()
{
    RestrictionGroup[] restrictions;

    static foreach(gr; getUDAs!(__traits(getMember, TYPE, symbol), RestrictionGroup))
        restrictions ~= gr;

    return restrictions;
}

private enum getRestrictionGroups(TYPE, typeof(null) symbol) = RestrictionGroup[].init;


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package struct Arguments
{
    ArgumentInfo[] arguments;

    // named arguments
    size_t[string] argsNamed;

    // positional arguments
    size_t[] argsPositional;

    Group[] userGroups;
    size_t[string] groupsByName;

    enum requiredGroupName = "Required arguments";
    enum optionalGroupName = "Optional arguments";
    Group requiredGroup = Group(requiredGroupName);
    Group optionalGroup = Group(optionalGroupName);

    Restriction[] restrictions;
    RestrictionGroup[] restrictionGroups;


    @property auto positionalArguments() const { return argsPositional; }


    void addArgument(TYPE, alias symbol, ArgumentInfo info)()
    {
        static if(hasMemberGroupUDA!(TYPE, symbol))
        {
            enum group = getMemberGroupUDA!(TYPE, symbol);

            auto index = (group.name in groupsByName);
            if(index !is null)
                addArgumentImpl!(TYPE, symbol, info)(userGroups[*index]);
            else
            {
                groupsByName[group.name] = userGroups.length;
                userGroups ~= group;
                addArgumentImpl!(TYPE, symbol, info)(userGroups[$-1]);
            }
        }
        else static if(info.required)
            addArgumentImpl!(TYPE, symbol, info)(requiredGroup);
        else
            addArgumentImpl!(TYPE, symbol, info)(optionalGroup);
    }

    private void addArgumentImpl(TYPE, alias symbol, ArgumentInfo info)(ref Group group)
    {
        static assert(info.names.length > 0);

        immutable index = arguments.length;

        static if(info.positional)
        {
            if(argsPositional.length <= info.position.get)
                argsPositional.length = info.position.get + 1;

            argsPositional[info.position.get] = index;
        }
        else
            static foreach(name; info.names)
            {
                assert(!(name in argsNamed), "Duplicated argument name: "~name);
                argsNamed[name] = index;
            }

        arguments ~= info;
        group.arguments ~= index;

        static if(info.required)
            restrictions ~= Restrictions.RequiredArg!info(index);

        static foreach(restriction; getRestrictionGroups!(TYPE, symbol))
            addRestriction!(info, restriction)(index);
    }

    void addRestriction(ArgumentInfo info, RestrictionGroup restriction)(size_t argIndex)
    {
        auto groupIndex = (restriction.location in groupsByName);
        auto index = groupIndex !is null
            ? *groupIndex
            : {
                auto index = groupsByName[restriction.location] = restrictionGroups.length;
                restrictionGroups ~= restriction;

                static if(restriction.required)
                    restrictions ~= (a,b,c) => Restrictions.RequiredAnyOf(a, b, c, restrictionGroups[index].arguments);

                enum checkFunc =
                    {
                        final switch(restriction.type)
                        {
                            case RestrictionGroup.Type.together:  return &Restrictions.RequiredTogether;
                            case RestrictionGroup.Type.exclusive: return &Restrictions.MutuallyExclusive;
                        }
                    }();

                restrictions ~= (a,b,c) => checkFunc(a, b, c, restrictionGroups[index].arguments);

                return index;
            }();

        restrictionGroups[index].arguments ~= argIndex;
    }


    Result checkRestrictions(in bool[size_t] cliArgs, Config* config) const
    {
        foreach(restriction; restrictions)
        {
            auto res = restriction(config, cliArgs, arguments);
            if(!res)
                return res;
        }

        return Result.Success;
    }


    struct FindResult
    {
        size_t index = size_t.max;
        const(ArgumentInfo)* arg;
    }

    FindResult findArgumentImpl(const size_t* pIndex) const
    {
        return pIndex ? FindResult(*pIndex, &arguments[*pIndex]) : FindResult.init;
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