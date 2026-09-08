module argparse.internal.restriction;

import argparse.config;
import argparse.helpprinter: HelpPrinter;
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

// Arguments that are required but were not provided are reported together, in one message that lists
// them the same way the help screen does so that their help text comes along.
package Result missingRequiredArgumentsError(const Config config, const(ArgumentInfo)[] args)
{
    import std.algorithm: map;
    import std.array: array;
    import std.string: chomp;

    assert(args.length > 0);

    scope hp = new HelpPrinter(config, config.styling);

    return Result.Error(config.errorExitCode,
        "The following argument", args.length > 1 ? "s are" : " is", " required:\n",
        hp.formatArgumentList(args.map!((ref _) => _.helpInfo).array).chomp);
}

unittest
{
    import argparse.style: Style;

    enum Config config = { styling: Style.None };

    static ArgumentInfo info(string name, string description)
    {
        ArgumentInfo res;
        res.longNames = [name];
        res.displayNames = ["--"~name];
        res.description = description;
        res.placeholder = "V";
        res.minValuesCount = 1;
        res.maxValuesCount = 1;
        res.required = true;
        return res;
    }

    // Single argument: singular wording
    assert(missingRequiredArgumentsError(config, [info("foo","descr")]).errorMessages ==
        ["The following argument is required:\n  --foo V    descr"]);

    // Multiple arguments: plural wording, and an argument without description is fine
    assert(missingRequiredArgumentsError(config, [info("foo","descr"), info("bar",null)]).errorMessages ==
        ["The following arguments are required:\n  --foo V    descr\n  --bar V"]);
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
        auto res = Result.Success;

        foreach(check; checks)
            res ~= check(cliArgs, argIndex);

        return res;
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


    // All checks are run: they are independent from each other, so reporting only the first failure
    // would hide the rest of what is wrong with the command line.
    package Result check(in size_t[size_t] cliArgs) const
    {
        auto res = Result.Success;

        foreach(check; checks)
            res ~= check(cliArgs);

        foreach(ref group; groups)
            res ~= group.check(cliArgs);

        return res;
    }
}

