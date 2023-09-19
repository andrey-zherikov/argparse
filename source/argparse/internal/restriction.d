module argparse.internal.restriction;

import argparse.config;
import argparse.result;
import argparse.internal.arguments: ArgumentInfo;

import std.traits: getUDAs;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private alias Restriction = Result delegate(in bool[size_t] cliArgs);

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) struct RestrictionGroup
{
    string location;

    enum Type { together, exclusive }
    Type type;

    bool required;

    private size_t[] argIndex;
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


private enum RequiredArg(Config config, ArgumentInfo info, size_t index) =
    (in bool[size_t] cliArgs)
    {
        return (index in cliArgs) ?
            Result.Success :
            Result.Error("The following argument is required: '", config.styling.argumentName(info.displayName), "'");
    };

private enum RequiredTogether(Config config, ArgumentInfo[] allArgs) =
    (in bool[size_t] cliArgs, in size_t[] restrictionArgs)
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
    };

private enum MutuallyExclusive(Config config, ArgumentInfo[] allArgs) =
    (in bool[size_t] cliArgs, in size_t[] restrictionArgs)
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
    };

private enum RequiredAnyOf(Config config, ArgumentInfo[] allArgs) =
    (in bool[size_t] cliArgs, in size_t[] restrictionArgs)
    {
        import std.algorithm: map;
        import std.array: join;

        foreach(index; restrictionArgs)
            if(index in cliArgs)
                return Result.Success;

        return Result.Error("One of the following arguments is required: '",
            restrictionArgs.map!(_ => config.styling.argumentName(allArgs[_].displayName)).join("', '"), "'");
    };

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package struct Restrictions
{
    private Restriction[] restrictions;
    private RestrictionGroup[] groups;
    private size_t[string] groupsByLocation;


    package void add(Config config, TYPE, ArgumentInfo[] infos)()
    {
        static foreach(argIndex, info; infos)
        {
            static if(info.required)
                restrictions ~= RequiredArg!(config, info, argIndex);

            static foreach(group; getRestrictionGroups!(TYPE, info.memberSymbol))
            {{
                auto groupIndex = (group.location in groupsByLocation);
                if(groupIndex !is null)
                    groups[*groupIndex].argIndex ~= argIndex;
                else
                {
                    auto gIndex = groupsByLocation[group.location] = groups.length;
                    groups ~= group;

                    static if(group.required)
                        restrictions ~= (in a) => RequiredAnyOf!(config, infos)(a, groups[gIndex].argIndex);

                    static if(group.type == RestrictionGroup.Type.together)
                        restrictions ~= (in a) => RequiredTogether!(config, infos)(a, groups[gIndex].argIndex);
                    else static if(group.type == RestrictionGroup.Type.exclusive)
                        restrictions ~= (in a) => MutuallyExclusive!(config, infos)(a, groups[gIndex].argIndex);
                    else static assert(false);

                    groups[gIndex].argIndex ~= argIndex;
                }
            }}
        }
    }




    package Result check(in bool[size_t] cliArgs) const
    {
        foreach(restriction; restrictions)
        {
            auto res = restriction(cliArgs);
            if(!res)
                return res;
        }

        return Result.Success;
    }
}

