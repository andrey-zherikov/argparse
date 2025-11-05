module argparse.internal.typetraits;

import argparse.config;
import argparse.api.subcommand: isSubCommand;
import argparse.internal.arguments: finalize;
import argparse.internal.argumentuda: ArgumentUDA;
import argparse.internal.argumentudahelpers: getMemberArgumentUDA, isArgumentUDA;
import argparse.internal.commandinfo;

import std.meta;
import std.string: startsWith;
import std.traits;


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private enum isPositional(alias uda) = uda.info.positional;
private enum hasPosition(alias uda) = !uda.info.position.isNull;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private enum isOpFunction(alias mem) = is(typeof(mem) == function) && __traits(identifier, mem).length > 2 && __traits(identifier, mem)[0..2] == "op";
private enum isConstructor(alias mem) = is(typeof(mem) == function) && __traits(identifier, mem) == "__ctor";

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private template Arguments(Config config, TYPE)
{
    // Discover potential arguments
    private template potentialArgument(string sym)
    {
        static if(is(TYPE == class) && __traits(hasMember, Object, sym))
            // If this is a member of Object class then skip it
            enum potentialArgument = false;
        else
        {
            alias mem = __traits(getMember, TYPE, sym);

            // Potential argument is:
            enum potentialArgument =
                !is(mem) &&                     // not a type               -- and --
                !isOpFunction!mem &&            // not operator function    -- and --
                !isConstructor!mem &&           // not a constructor        -- and --
                !isSubCommand!(typeof(mem));    // not subcommand
        }
    }

    private enum allMembers = Filter!(potentialArgument, __traits(allMembers, TYPE));

    private alias hasArgumentUDA(string sym) = anySatisfy!(isArgumentUDA, __traits(getAttributes, __traits(getMember, TYPE, sym)));

    private enum membersWithUDA = Filter!(hasArgumentUDA, allMembers);

    // Get argument UDAs: if there are no members attributed with UDA then get all members, otherwise only attributed ones
    private enum getArgumentUDA(string sym) = getMemberArgumentUDA!(TYPE, sym)(config);

    static if(membersWithUDA.length == 0)
    {
        // No argument UDAs are used so all arguments are named and we can skip processing of positional UDAs
        private enum UDAs = staticMap!(getArgumentUDA, allMembers);

        private enum hasOptionalPositional = false;
    }
    else
    {
        private enum UDAs = staticMap!(getArgumentUDA, membersWithUDA);

        // Ensure that we don't have a mix of user-dfined and automatic positions of arguments
        private enum positionalWithPos(alias uda) = isPositional!uda && hasPosition!uda;
        private enum positionalWithoutPos(alias uda) = isPositional!uda && !hasPosition!uda;

        private enum positionalWithPosNum = Filter!(positionalWithPos, UDAs).length;

        static assert(positionalWithPosNum == 0 || Filter!(positionalWithoutPos, UDAs).length == 0,
            TYPE.stringof~": Positions must be specified for all or none positional arguments");

        static if(positionalWithPosNum == 0)
        {
            private enum positionalUDAs = Filter!(isPositional, UDAs);
        }
        else
        {
            private enum sortByPosition(alias uda1, alias uda2) = uda1.info.position.get - uda2.info.position.get;

            private enum positionalUDAs = staticSort!(sortByPosition, Filter!(isPositional, UDAs));

            static foreach(i, uda; positionalUDAs)
            {
                static if(i < uda.info.position.get)
                    static assert(false, TYPE.stringof~": Positional argument with index "~i.stringof~" is missed");
                else static if(i > uda.info.position.get)
                    static assert(false, TYPE.stringof~": Positional argument with index "~uda.info.position.get.stringof~" is duplicated");
            }
        }

        static foreach(i, uda; positionalUDAs)
        {
            static if(i < positionalUDAs.length - 1)
                static assert(uda.info.minValuesCount.get == uda.info.maxValuesCount.get,
                    TYPE.stringof~": Positional argument with index "~i.stringof~" has variable number of values - only last one is allowed to have it");

            static if(i > 0 && uda.info.required)
                static assert(positionalUDAs[i-1].info.required,
                    TYPE.stringof~": Required positional argument with index "~i.stringof~" can't come after optional positional argument");
        }

        private enum hasOptionalPositional = positionalUDAs.length > 0 && !positionalUDAs[$-1].info.required;
    }

    private enum getInfo(alias uda) = uda.info;
    private enum infos = staticMap!(getInfo, UDAs);

    // Check whether argument names do not violate argparse requirements
    static foreach(info; infos)
    {
        static foreach (name; info.shortNames)
            static assert(!name.startsWith(config.shortNamePrefix), TYPE.stringof~": Argument name should not begin with '"~config.shortNamePrefix~"': "~name);
        static foreach (name; info.longNames)
            static assert(!name.startsWith(config.longNamePrefix), TYPE.stringof~": Argument name should not begin with '"~config.longNamePrefix~"': "~name);
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private template SubCommands(Config config, TYPE)
{
    private template isSubCommandSymbol(string sym)
    {
        alias mem = __traits(getMember, TYPE, sym);

        enum isSubCommandSymbol =
            !is(mem) &&                     // not a type   -- and --
            .isSubCommand!(typeof(mem));    // subcommand
    }

    private alias symbols = Filter!(isSubCommandSymbol, __traits(allMembers, TYPE));
    static assert(symbols.length <= 1, TYPE.stringof~": Multiple subcommand members: "~symbols.stringof);

    static if(symbols.length == 1)
    {
        private enum symbol = symbols[0];

        private alias memberType = typeof(__traits(getMember, TYPE, symbol));

        private enum getCommandInfo(alias CMD) = .getSubCommandInfo!CMD(config, is(memberType.DefaultCommand == CMD));
        private enum commands = staticMap!(getCommandInfo, memberType.Types);

        private enum isDefault(alias CMD) = CMD.isDefault;
        private enum defaultSubCommands = Filter!(isDefault, commands);

        // Check whether names of subcommands do not violate argparse requirements
        static foreach(cmd; commands)
            static foreach(name; cmd.names)
            {
                static assert(!name.startsWith(config.shortNamePrefix), TYPE.stringof~": Subcommand name should not begin with '"~config.shortNamePrefix~"': "~name);
                static assert(!name.startsWith(config.longNamePrefix), TYPE.stringof~": Subcommand name should not begin with '"~config.longNamePrefix~"': "~name);
            }
    }
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) template TypeTraits(Config config, TYPE)
{
    /////////////////////////////////////////////////////////////////////
    /// Arguments

    private alias arguments = .Arguments!(config, TYPE);

    alias argumentUDAs = arguments.UDAs;
    alias argumentInfos = arguments.infos;

    /////////////////////////////////////////////////////////////////////
    /// Subcommands

    private alias SC = .SubCommands!(config, TYPE);

    static if(is(typeof(SC.commands)))
    {
        alias subCommandSymbol = SC.symbol;
        alias subCommands = SC.commands;

        static if(SC.defaultSubCommands.length > 0)
        {
            alias defaultSubCommand = SC.defaultSubCommands[0];

            static assert(!arguments.hasOptionalPositional, TYPE.stringof~": Optional positional arguments and default subcommand can't be used together in one command");
        }
    }
}
