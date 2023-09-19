module argparse.internal.restriction;

import argparse.config;
import argparse.result;
import argparse.internal.arguments: ArgumentInfo;

import std.traits: getUDAs;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private alias Restriction = Result delegate(in bool[size_t] cliArgs, in ArgumentInfo[] allArgs);

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

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private auto getRestrictionGroups(TYPE, string symbol)()
{
    RestrictionGroup[] restrictions;

    static foreach(gr; getUDAs!(__traits(getMember, TYPE, symbol), RestrictionGroup))
        restrictions ~= gr;

    return restrictions;
}

private enum getRestrictionGroups(TYPE, typeof(null) symbol) = RestrictionGroup[].init;

unittest
{
    struct T
    {
        @(RestrictionGroup("1"))
        @(RestrictionGroup("2"))
        @(RestrictionGroup("3"))
        int a;
    }

    assert(getRestrictionGroups!(T, "a") == [RestrictionGroup("1"), RestrictionGroup("2"), RestrictionGroup("3")]);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////



private Restriction RequiredArg(Config config, ArgumentInfo info, size_t index)()
{
    return (in bool[size_t] cliArgs, in ArgumentInfo[] allArgs)
    {
        return (index in cliArgs) ?
            Result.Success :
            Result.Error("The following argument is required: '", config.styling.argumentName(info.displayName), "'");
    };
}

private Result RequiredTogether(Config config)
                              (in bool[size_t] cliArgs,
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
            return Result.Error("Missed argument '", config.styling.argumentName(allArgs[missedIndex].displayName),
                "' - it is required by argument '", config.styling.argumentName(allArgs[foundIndex].displayName), "'");
    }

    return Result.Success;
}

private Result MutuallyExclusive(Config config)
                               (in bool[size_t] cliArgs,
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
                return Result.Error("Argument '", config.styling.argumentName(allArgs[foundIndex].displayName),
                    "' is not allowed with argument '", config.styling.argumentName(allArgs[index].displayName),"'");
        }

    return Result.Success;
}

private Result RequiredAnyOf(Config config)
                           (in bool[size_t] cliArgs,
                            in ArgumentInfo[] allArgs,
                            in size_t[] restrictionArgs)
{
    import std.algorithm: map;
    import std.array: join;

    foreach(index; restrictionArgs)
        if(index in cliArgs)
            return Result.Success;

    return Result.Error("One of the following arguments is required: '",
        restrictionArgs.map!(_ => config.styling.argumentName(allArgs[_].displayName)).join("', '"), "'");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package struct Restrictions
{
    Restriction[] restrictions;
    RestrictionGroup[] groups;
    size_t[string] groupsByLocation;


    private auto addGroup(Config config, RestrictionGroup group)()
    {
        auto index = groupsByLocation[group.location] = groups.length;
        groups ~= group;

        static if(group.required)
            restrictions ~= (in a, in b) => RequiredAnyOf!config(a, b, groups[index].arguments);

        static if(group.type == RestrictionGroup.Type.together)
            restrictions ~= (in a, in b) => RequiredTogether!config(a, b, groups[index].arguments);
        else static if(group.type == RestrictionGroup.Type.exclusive)
            restrictions ~= (in a, in b) => MutuallyExclusive!config(a, b, groups[index].arguments);
        else static assert(false);

        return index;
    }

    private void add(Config config, RestrictionGroup group, size_t argIndex)()
    {
        auto groupIndex = (group.location in groupsByLocation);
        auto index = groupIndex !is null
            ? *groupIndex
            : addGroup!(config, group);

        groups[index].arguments ~= argIndex;
    }


    package void add(Config config, TYPE, infos...)()
    {
        static foreach(index, info; infos)
        {
            static if(info.required)
                restrictions ~= RequiredArg!(config, info, index);

            static foreach(group; getRestrictionGroups!(TYPE, info.memberSymbol))
                add!(config, group, index);
        }
    }




    package Result check(in bool[size_t] cliArgs, in ArgumentInfo[] arguments) const
    {
        foreach(restriction; restrictions)
        {
            auto res = restriction(cliArgs, arguments);
            if(!res)
                return res;
        }

        return Result.Success;
    }
}

