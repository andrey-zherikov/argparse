module argparse.internal.command;

import argparse.config;
import argparse.param;
import argparse.result;
import argparse.api.subcommand: match;
import argparse.internal.arguments: Arguments, ArgumentInfo;
import argparse.internal.argumentudahelpers: getMemberArgumentUDA;
import argparse.internal.commandinfo;
import argparse.internal.restriction;
import argparse.internal.typetraits;

import std.meta;


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private struct SubCommands
{
    size_t[string] byName;

    CommandInfo[] info;


    void add(CommandInfo[] cmdInfo)
    {
        info = cmdInfo;

        foreach(index, info; cmdInfo)
            foreach(name; info.names)
            {
                assert(!(name in byName), "Duplicated name of subcommand: "~name);
                byName[name] = index;
            }
    }

    size_t find(string name) const
    {
        import std.uni: toUpper;

        auto pIndex = name in byName;
        if(pIndex)
            return *pIndex;

        pIndex = name.toUpper in byName;
        return (!pIndex || info[*pIndex].caseSensitive) ? size_t(-1) : *pIndex;
    }
}


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private Result ArgumentParsingFunction(alias uda, RECEIVER)(const Command[] cmdStack,
                                                            ref RECEIVER receiver,
                                                            ref RawParam param)
{
    static if(uda.info.memberSymbol)
        auto target = &__traits(getMember, receiver, uda.info.memberSymbol);
    else
        auto target = null;

    static if(is(typeof(target) == typeof(null)) || is(typeof(target) == function) || is(typeof(target) == delegate))
        return uda.parse(cmdStack, target, param);
    else
        return uda.parse(cmdStack, *target, param);
}

private Result ArgumentCompleteFunction(alias uda, RECEIVER)(const Command[] cmdStack,
                                                             ref RECEIVER receiver,
                                                             ref RawParam param)
{
    return Result.Success;
}


unittest
{
    struct T
    {
        void func() { throw new Exception("My Message."); }
    }

    T t;
    Config cfg;
    auto param = RawParam(&cfg, "func", []);

    enum uda = getMemberArgumentUDA!(T, "func")(Config.init);

    auto res = ArgumentParsingFunction!uda([], t, param);

    assert(res.isError("func",": My Message."));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package struct Command
{
    alias Parse = Result delegate(const Command[] cmdStack,ref RawParam param);

    struct Argument
    {
        const(ArgumentInfo)* info;

        Parse parse;
        Parse complete;

        bool opCast(T : bool)() const
        {
            return info !is null;
        }
    }

    private Parse[] parseFuncs;
    private Parse[] completeFuncs;

    private Parse getParseFunc(Parse[] funcs, size_t index)
    {
        return (stack, ref param)
        {
            idxParsedArgs[index] = true;
            return funcs[index](stack, param);
        };
    }


    auto findShortNamedArgument(string name)
    {
        auto res = arguments.findShortNamedArgument(name);
        if(!res.arg)
            return Argument.init;

        return Argument(res.arg, getParseFunc(parseFuncs, res.index), getParseFunc(completeFuncs, res.index));
    }

    auto findLongNamedArgument(string name)
    {
        auto res = arguments.findLongNamedArgument(name);
        if(!res.arg)
            return Argument.init;

        return Argument(res.arg, getParseFunc(parseFuncs, res.index), getParseFunc(completeFuncs, res.index));
    }

    auto findPositionalArgument(size_t position)
    {
        auto res = arguments.findPositionalArgument(position);
        if(!res.arg)
            return Argument.init;

        return Argument(res.arg, getParseFunc(parseFuncs, res.index), getParseFunc(completeFuncs, res.index));
    }



    const(string)[] suggestions(string prefix) const
    {
        import std.range: chain;
        import std.algorithm: filter, map;
        import std.string: startsWith;
        import std.array: array, join;

        // suggestions are names of all arguments and subcommands
        auto suggestions_ = chain(arguments.namedArguments.filter!((ref _) => !_.hidden).map!((ref _) => _.displayNames).join, subCommands.byName.keys);

        // empty prefix means that we need to provide all suggestions, otherwise they are filtered
        return prefix == "" ? suggestions_.array : suggestions_.filter!(_ => _.startsWith(prefix)).array;
    }


    Arguments arguments;

    bool[size_t] idxParsedArgs;

    Restrictions restrictions;

    CommandInfo info;

    string displayName() const { return info.displayNames.length > 0 ? info.displayNames[0] : ""; }

    SubCommands subCommands;
    Command delegate() [] subCommandCreate;
    Command delegate() defaultSubCommand;

    auto getSubCommand(string name) const
    {
        auto idx = subCommands.find(name);
        return idx != size_t(-1) ? subCommandCreate[idx] : null;
    }

    Result checkRestrictions() const
    {
        return restrictions.check(idxParsedArgs);
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) Command createCommand(Config config, COMMAND_TYPE)(ref COMMAND_TYPE receiver, CommandInfo info)
{
    alias typeTraits = TypeTraits!(config, COMMAND_TYPE);

    Command res;

    res.info = info;
    res.arguments.add!(COMMAND_TYPE, [typeTraits.argumentInfos]);
    res.restrictions.add!(COMMAND_TYPE, [typeTraits.argumentInfos])(config);

    enum getArgumentParsingFunction(alias uda) =
         (const Command[] cmdStack, ref RawParam param) => ArgumentParsingFunction!uda(cmdStack, receiver, param);

    res.parseFuncs = [staticMap!(getArgumentParsingFunction, typeTraits.argumentUDAs)];

    enum getArgumentCompleteFunction(alias uda) =
        (const Command[] cmdStack, ref RawParam param) => ArgumentCompleteFunction!uda(cmdStack, receiver, param);

    res.completeFuncs = [staticMap!(getArgumentCompleteFunction, typeTraits.argumentUDAs)];

    static if(is(typeof(typeTraits.subCommands)))
    {
        alias createFunc(alias CMD) = () => ParsingSubCommandCreate!(config, CMD.TYPE)(
            __traits(getMember, receiver, typeTraits.subCommandSymbol),
            CMD,
        );

        res.subCommandCreate = [staticMap!(createFunc, typeTraits.subCommands)];
        res.subCommands.add([typeTraits.subCommands]);

        static if(is(typeof(typeTraits.defaultSubCommand)))
            res.defaultSubCommand = createFunc!(typeTraits.defaultSubCommand);
    }

    return res;
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private auto ParsingSubCommandCreate(Config config, COMMAND_TYPE, TARGET)(ref TARGET target, CommandInfo info)
{
    alias create = (ref COMMAND_TYPE actualTarget) =>
        createCommand!(config, COMMAND_TYPE)(actualTarget, info);

    // Initialize if needed
    if(!target.isSetTo!COMMAND_TYPE)
        target = COMMAND_TYPE.init;

    static if(TARGET.Types.length == 1)
        return target.match!create;
    else
    {
        return target.match!(create,
            function Command(_)
            {
                assert(false, "This should never happen");
            }
        );
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
