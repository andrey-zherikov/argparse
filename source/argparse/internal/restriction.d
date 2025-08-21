module argparse.internal.restriction;

import argparse.config;
import argparse.result;
import argparse.internal.arguments: ArgumentInfo;


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private auto CheckNumberOfValues(const Config config, const ArgumentInfo info, size_t index)
{
    return (in size_t[size_t] cliArgs)
    {
        return (index in cliArgs) ?
            info.checkValuesCount(&config, info.displayName, cliArgs[index]) :
            Result.Success;
    };
}

unittest
{
    ArgumentInfo info;
    info.displayNames = ["-foo"];
    info.minValuesCount = 2;
    info.maxValuesCount = 4;

    auto f = CheckNumberOfValues(Config.init, info, 0);

    assert(f((size_t[size_t]).init));
    assert(f([1:3]));

    assert(f([0:1]).isError("Argument","expected at least 2 values"));
    assert(f([0:2]));
    assert(f([0:3]));
    assert(f([0:4]));
    assert(f([0:5]).isError("Argument","expected at most 4 values"));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private auto RequiredArg(const Config config, const ArgumentInfo info, size_t index)
{
    return (in size_t[size_t] cliArgs)
    {
        return (index in cliArgs) ?
            Result.Success :
            Result.Error(config.errorExitCode, "The following argument is required: '", config.styling.argumentName(info.displayName), "'");
    };
}

unittest
{
    auto f = RequiredArg(Config.init, ArgumentInfo([],[],[""]), 0);

    assert(f((size_t[size_t]).init).isError("argument is required"));

    assert(f([1:1]).isError("argument is required"));

    assert(f([0:1]));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private auto RequiredTogether(const Config config, const(ArgumentInfo)[] allArgs)
{
    return (in size_t[size_t] cliArgs, in size_t[] restrictionArgs)
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
                return Result.Error(config.errorExitCode, "Missed argument '", config.styling.argumentName(allArgs[missedIndex].displayName),
                    "' - it is required by argument '", config.styling.argumentName(allArgs[foundIndex].displayName), "'");
        }

        return Result.Success;
    };
}


unittest
{
    auto f = RequiredTogether(Config.init, [ArgumentInfo([],[],["--a"]), ArgumentInfo([],[],["--b"]), ArgumentInfo([],[],["--c"])]);

    assert(f((size_t[size_t]).init, [0,1]));

    assert(f([0:1], [0,1]).isError("Missed argument","--a"));
    assert(f([1:1], [0,1]).isError("Missed argument","--b"));

    assert(f([0:1, 1:1], [0,1]));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private auto RequiredAnyOf(const Config config, const(ArgumentInfo)[] allArgs)
{
    return (in size_t[size_t] cliArgs, in size_t[] restrictionArgs)
    {
        import std.algorithm: map;
        import std.array: join;

        foreach(index; restrictionArgs)
            if(index in cliArgs)
                return Result.Success;

        return Result.Error(config.errorExitCode, "One of the following arguments is required: '",
            restrictionArgs.map!(_ => config.styling.argumentName(allArgs[_].displayName)).join("', '"), "'");
    };
}


unittest
{
    auto f = RequiredAnyOf(Config.init, [ArgumentInfo([],[],["--a"]), ArgumentInfo([],[],["--b"]), ArgumentInfo([],[],["--c"])]);

    assert(f((size_t[size_t]).init, [0,1]).isError("One of the following arguments is required","--a","--b"));
    assert(f([2:1], [0,1]).isError("One of the following arguments is required","--a","--b"));

    assert(f([0:1], [0,1]));
    assert(f([1:1], [0,1]));

    assert(f([0:1, 1:1], [0,1]));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private auto MutuallyExclusive(const Config config, const(ArgumentInfo)[] allArgs)
{
    return (in size_t[size_t] cliArgs, in size_t[] restrictionArgs)
    {
        size_t foundIndex = size_t.max;

        foreach(index; restrictionArgs)
            if(index in cliArgs)
            {
                if(foundIndex == size_t.max)
                    foundIndex = index;
                else
                    return Result.Error(config.errorExitCode, "Argument '", config.styling.argumentName(allArgs[foundIndex].displayName),
                        "' is not allowed with argument '", config.styling.argumentName(allArgs[index].displayName),"'");
            }

        return Result.Success;
    };
}


unittest
{
    auto f = MutuallyExclusive(Config.init, [ArgumentInfo([],[],["--a"]), ArgumentInfo([],[],["--b"]), ArgumentInfo([],[],["--c"])]);

    assert(f((size_t[size_t]).init, [0,1]));

    assert(f([0:1], [0,1]));
    assert(f([1:1], [0,1]));
    assert(f([2:1], [0,1]));

    assert(f([0:1, 2:1], [0,1]));
    assert(f([1:1, 2:1], [0,1]));

    assert(f([0:1, 1:1], [0,1]).isError("is not allowed with argument","--a","--b"));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) struct RestrictionGroup
{
    string location;

    enum Type { together, exclusive }
    Type type;

    bool required;

    private size_t[] argIndex;


    private Result delegate(in size_t[size_t] cliArgs, in size_t[] argIndex)[] checks;

    private void initialize(ref const Config config, const(ArgumentInfo)[] infos)
    {
        if(required)
            checks ~= RequiredAnyOf(config, infos);

        final switch(type)
        {
            case Type.together:     checks ~= RequiredTogether (config, infos);    break;
            case Type.exclusive:    checks ~= MutuallyExclusive(config, infos);    break;
        }
    }

    private Result check(in size_t[size_t] cliArgs) const
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

private template getRestrictionGroups(alias member)
{
    import std.meta: Filter;

    enum isRestriction(alias uda) = is(typeof(uda) == RestrictionGroup);

    enum getRestrictionGroups = Filter!(isRestriction, __traits(getAttributes, member));
}

unittest
{
    struct T
    {
        @(RestrictionGroup("1"))
        @(RestrictionGroup("2"))
        @(RestrictionGroup("3"))
        int a;
    }

    assert([getRestrictionGroups!(T.a)] == [RestrictionGroup("1"), RestrictionGroup("2"), RestrictionGroup("3")]);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package struct Restrictions
{
    private Result delegate(in size_t[size_t] cliArgs)[] checks;
    private RestrictionGroup[] groups;
    private size_t[string] groupsByLocation;


    package void add(TYPE, ArgumentInfo[] infos)(Config config)
    {
        static foreach(argIndex, info; infos)
            static if(info.memberSymbol !is null)   // to skip HelpArgumentUDA
            {
                if(config.variadicNamedArgument)
                    checks ~= CheckNumberOfValues(config, info, argIndex);

                static if(info.required)
                    checks ~= RequiredArg(config, info, argIndex);

                static foreach(group; getRestrictionGroups!(__traits(getMember, TYPE, info.memberSymbol)))
                {{
                    auto groupIndex = (group.location in groupsByLocation);
                    if(groupIndex !is null)
                        groups[*groupIndex].argIndex ~= argIndex;
                    else
                    {
                        auto gIndex = groupsByLocation[group.location] = groups.length;
                        groups ~= group;

                        groups[gIndex].initialize(config, infos);
                        groups[gIndex].argIndex ~= argIndex;
                    }
                }}
            }
    }


    package Result check(in size_t[size_t] cliArgs) const
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

