module argparse.internal.restriction;

import argparse.config;
import argparse.result;
import argparse.internal.arguments: ArgumentInfo;

import std.traits: getUDAs;


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


private enum RequiredArg(Config config, ArgumentInfo info, size_t index) =
    (in bool[size_t] cliArgs)
    {
        return (index in cliArgs) ?
            Result.Success :
            Result.Error("The following argument is required: '", config.styling.argumentName(info.displayName), "'");
    };

unittest
{
    auto f = RequiredArg!(Config.init, ArgumentInfo([""], [""]), 0);

    assert(f(bool[size_t].init).isError("argument is required"));

    assert(f([1:true]).isError("argument is required"));

    assert(f([0:true]));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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


unittest
{
    auto f = RequiredTogether!(Config.init, [ArgumentInfo([], ["--a"]), ArgumentInfo([], ["--b"]), ArgumentInfo([], ["--c"])]);

    assert(f(bool[size_t].init, [0,1]));

    assert(f([0:true], [0,1]).isError("Missed argument","--a"));
    assert(f([1:true], [0,1]).isError("Missed argument","--b"));

    assert(f([0:true, 1:true], [0,1]));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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


unittest
{
    auto f = RequiredAnyOf!(Config.init, [ArgumentInfo([], ["--a"]), ArgumentInfo([], ["--b"]), ArgumentInfo([], ["--c"])]);

    assert(f(bool[size_t].init, [0,1]).isError("One of the following arguments is required","--a","--b"));
    assert(f([2:true], [0,1]).isError("One of the following arguments is required","--a","--b"));

    assert(f([0:true], [0,1]));
    assert(f([1:true], [0,1]));

    assert(f([0:true, 1:true], [0,1]));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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


unittest
{
    auto f = MutuallyExclusive!(Config.init, [ArgumentInfo([], ["--a"]), ArgumentInfo([], ["--b"]), ArgumentInfo([], ["--c"])]);

    assert(f(bool[size_t].init, [0,1]));

    assert(f([0:true], [0,1]));
    assert(f([1:true], [0,1]));
    assert(f([2:true], [0,1]));

    assert(f([0:true, 2:true], [0,1]));
    assert(f([1:true, 2:true], [0,1]));

    assert(f([0:true, 1:true], [0,1]).isError("is not allowed with argument","--a","--b"));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) struct RestrictionGroup
{
    string location;

    enum Type { together, exclusive }
    Type type;

    bool required;

    private size_t[] argIndex;


    private Result function(in bool[size_t] cliArgs, in size_t[] argIndex)[] checks;

    private void initialize(Config config, ArgumentInfo[] infos)()
    {
        if(required)
            checks ~= RequiredAnyOf!(config, infos);

        final switch(type)
        {
            case Type.together:     checks ~= RequiredTogether !(config, infos);    break;
            case Type.exclusive:    checks ~= MutuallyExclusive!(config, infos);    break;
        }
    }

    private Result check(in bool[size_t] cliArgs) const
    {
        foreach(check; checks)
        {
            auto res = check(cliArgs, argIndex);
            if(!res)
                return res;
        }

        return Result.Success;
    }
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

package struct Restrictions
{
    private Result function(in bool[size_t] cliArgs)[] checks;
    private RestrictionGroup[] groups;
    private size_t[string] groupsByLocation;


    package void add(Config config, TYPE, ArgumentInfo[] infos)()
    {
        static foreach(argIndex, info; infos)
        {
            static if(info.required)
                checks ~= RequiredArg!(config, info, argIndex);

            static foreach(group; getRestrictionGroups!(TYPE, info.memberSymbol))
            {{
                auto groupIndex = (group.location in groupsByLocation);
                if(groupIndex !is null)
                    groups[*groupIndex].argIndex ~= argIndex;
                else
                {
                    auto gIndex = groupsByLocation[group.location] = groups.length;
                    groups ~= group;

                    groups[gIndex].initialize!(config, infos);
                    groups[gIndex].argIndex ~= argIndex;
                }
            }}
        }
    }


    package Result check(in bool[size_t] cliArgs) const
    {
        foreach(check; checks)
        {
            auto res = check(cliArgs);
            if(!res)
                return res;
        }

        foreach(ref group; groups)
        {
            auto res = group.check(cliArgs);
            if(!res)
                return res;
        }

        return Result.Success;
    }
}

