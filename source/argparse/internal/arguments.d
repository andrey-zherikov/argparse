module argparse.internal.arguments;

import argparse.internal: getArgumentName, CommandArguments;
import argparse.internal.utils: partiallyApply;
import argparse.internal.lazystring;

import argparse.api: Config, Result, RawParam;

import std.typecons: Nullable;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) struct ArgumentInfo
{
    string[] names;

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
                Result.Error("The following argument is required: ", info.getArgumentName(config.namedArgChar));
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
                return Result.Error("Missed argument '", allArgs[missedIndex].getArgumentName(config.namedArgChar),
                                    "' - it is required by argument '", allArgs[foundIndex].getArgumentName(config.namedArgChar),"'");
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
                    return Result.Error("Argument '", allArgs[foundIndex].getArgumentName(config.namedArgChar),
                                        "' is not allowed with argument '", allArgs[index].getArgumentName(config.namedArgChar),"'");
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

        return Result.Error("One of the following arguments is required: '", restrictionArgs.map!(_ => allArgs[_].getArgumentName(config.namedArgChar)).join("', '"), "'");
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) struct Group
{
    string name;
    LazyString description;
    size_t[] arguments;
}

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

package struct Arguments
{
    immutable string function(string str) convertCase;

    ArgumentInfo[] arguments;

    // named arguments
    size_t[string] argsNamed;

    // positional arguments
    size_t[] argsPositional;

    const Arguments* parentArguments;

    Group[] groups;
    enum requiredGroupIndex = 0;
    enum optionalGroupIndex = 1;

    size_t[string] groupsByName;

    Restriction[] restrictions;
    RestrictionGroup[] restrictionGroups;

    @property ref Group requiredGroup() { return groups[requiredGroupIndex]; }
    @property ref const(Group) requiredGroup() const { return groups[requiredGroupIndex]; }
    @property ref Group optionalGroup() { return groups[optionalGroupIndex]; }
    @property ref const(Group) optionalGroup() const { return groups[optionalGroupIndex]; }

    @property auto positionalArguments() const { return argsPositional; }


    this(bool caseSensitive, const Arguments* parentArguments = null)
    {
        if(caseSensitive)
            convertCase = s => s;
        else
            convertCase = (string str)
            {
                import std.uni : toUpper;
                return str.toUpper;
            };

        this.parentArguments = parentArguments;

        groups = [ Group("Required arguments"), Group("Optional arguments") ];
    }

    void addArgument(ArgumentInfo info, RestrictionGroup[] restrictions, Group group)()
    {
        auto index = (group.name in groupsByName);
        if(index !is null)
            addArgument!(info, restrictions)(groups[*index]);
        else
        {
            groupsByName[group.name] = groups.length;
            groups ~= group;
            addArgument!(info, restrictions)(groups[$-1]);
        }
    }

    void addArgument(ArgumentInfo info, RestrictionGroup[] restrictions = [])()
    {
        static if(info.required)
            addArgument!(info, restrictions)(requiredGroup);
        else
            addArgument!(info, restrictions)(optionalGroup);
    }

    private void addArgument(ArgumentInfo info, RestrictionGroup[] argRestrictions = [])( ref Group group)
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
                argsNamed[convertCase(name)] = index;
            }

        arguments ~= info;
        group.arguments ~= index;

        static if(info.required)
            restrictions ~= Restrictions.RequiredArg!info(index);

        static foreach(restriction; argRestrictions)
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


    auto findArgumentImpl(const size_t* pIndex) const
    {
        struct Result
        {
            size_t index = size_t.max;
            const(ArgumentInfo)* arg;
        }

        return pIndex ? Result(*pIndex, &arguments[*pIndex]) : Result.init;
    }

    auto findPositionalArgument(size_t position) const
    {
        return findArgumentImpl(position < argsPositional.length ? &argsPositional[position] : null);
    }

    auto findNamedArgument(string name) const
    {
        return findArgumentImpl(convertCase(name) in argsNamed);
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package alias ParseFunction(RECEIVER) = Result delegate(Config* config, const ref CommandArguments!RECEIVER cmd, string argName, ref RECEIVER receiver, string rawValue, ref string[] rawArgs);

package alias ParsingArgument(alias symbol, alias uda, ArgumentInfo info, RECEIVER, bool completionMode) =
    delegate(Config* config, const ref CommandArguments!RECEIVER cmd, string argName, ref RECEIVER receiver, string rawValue, ref string[] rawArgs)
    {
        static if(completionMode)
        {
            if(rawValue is null)
                consumeValuesFromCLI(rawArgs, info.minValuesCount.get, info.maxValuesCount.get, config.namedArgChar);

            return Result.Success;
        }
        else
        {
            try
            {
                auto rawValues = rawValue !is null ? [ rawValue ] : consumeValuesFromCLI(rawArgs, info.minValuesCount.get, info.maxValuesCount.get, config.namedArgChar);

                auto res = info.checkValuesCount(argName, rawValues.length);
                if(!res)
                    return res;

                auto param = RawParam(config, argName, rawValues);

                auto target = &__traits(getMember, receiver, symbol);

                static if(is(typeof(target) == function) || is(typeof(target) == delegate))
                    return uda.parsingFunc.parse(target, param);
                else
                    return uda.parsingFunc.parse(*target, param);
            }
            catch(Exception e)
            {
                return Result.Error(argName, ": ", e.msg);
            }
        }
    };

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private auto consumeValuesFromCLI(ref string[] args, ulong minValuesCount, ulong maxValuesCount, char namedArgChar)
{
    import std.range: empty, front, popFront;

    string[] values;

    if(minValuesCount > 0)
    {
        if(minValuesCount < args.length)
        {
            values = args[0..minValuesCount];
            args = args[minValuesCount..$];
        }
        else
        {
            values = args;
            args = [];
        }
    }

    while(!args.empty &&
        values.length < maxValuesCount &&
        (args.front.length == 0 || args.front[0] != namedArgChar))
    {
        values ~= args.front;
        args.popFront();
    }

    return values;
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
