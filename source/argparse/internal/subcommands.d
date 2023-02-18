module argparse.internal.subcommands;

import argparse.config;
import argparse.result;
import argparse.api.command: SubCommandsUDA = SubCommands, isDefaultCommand, RemoveDefaultAttribute;
import argparse.internal.commandinfo;
import argparse.internal.command: Command, createCommand;
import argparse.internal.lazystring;
import argparse.internal: hasNoMembersWithUDA, isOpFunction;

import std.sumtype: match, isSumType;
import std.traits;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package enum DEFAULT_COMMAND = "";

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private alias CreateSubCommandFunction(RECEIVER) = Command function(ref RECEIVER receiver) pure nothrow;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


package struct SubCommands(RECEIVER)
{
    size_t[string] byName;

    CommandInfo[] info;
    CreateSubCommandFunction!RECEIVER[] createFunc;


    void add(Config config, alias symbol, SUBCOMMAND, COMMAND)()
    {
        //static assert(getUDAs!(member, Group).length <= 1,
        //    "Member "~COMMAND.stringof~"."~symbol~" has multiple 'Group' UDAs");

        //static if(getUDAs!(member, Group).length > 0)
        //    args.addArgument!(info, restrictions, getUDAs!(member, Group)[0])(ParsingArgument!(symbol, uda, info, COMMAND));
        //else
        //arguments.addSubCommand!(info);

        immutable index = info.length;

        enum cmdInfo = getCommandInfo!(config, RemoveDefaultAttribute!SUBCOMMAND, RemoveDefaultAttribute!SUBCOMMAND.stringof);

        static foreach(name; cmdInfo.names)
        {{
            assert(!(name in byName), "Duplicated name of subcommand: "~name);
            byName[name] = index;
        }}

        static if(isDefaultCommand!SUBCOMMAND)
        {
            assert(!(DEFAULT_COMMAND in byName), "Multiple default subcommands: "~COMMAND.stringof~"."~symbol);
            byName[DEFAULT_COMMAND] = index;
        }

        info ~= cmdInfo;
        createFunc ~= ParsingSubCommandCreate!(config, SUBCOMMAND, cmdInfo, COMMAND, symbol);
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package auto ParsingSubCommandCreate(Config config, COMMAND_TYPE, CommandInfo info, RECEIVER, alias symbol)()
{
    return function (ref RECEIVER receiver)
    {
        auto target = &__traits(getMember, receiver, symbol);

        alias create = (ref COMMAND_TYPE actualTarget)
            => createCommand!(config, RemoveDefaultAttribute!COMMAND_TYPE, info)(actualTarget);

        static if(typeof(*target).Types.length == 1)
            return (*target).match!create;
        else
        {
            // Initialize if needed
            if((*target).match!((ref COMMAND_TYPE t) => false, _ => true))
                *target = COMMAND_TYPE.init;

            return (*target).match!(create,
                (_)
                {
                    assert(false, "This should never happen");
                    return Command.init;
                }
            );
        }
    };
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package auto createSubCommands(Config config, COMMAND)()
{
    enum isSubCommand(alias mem) = hasUDA!(mem, SubCommandsUDA) ||
                                   hasNoMembersWithUDA!COMMAND && !isOpFunction!mem && isSumType!(typeof(mem));

    SubCommands!COMMAND subCommands;

    static foreach(sym; __traits(allMembers, COMMAND))
    {{
        alias mem = __traits(getMember, COMMAND, sym);

        // skip types
        static if(!is(mem) && isSubCommand!mem)
        {
            static assert(isSumType!(typeof(mem)), COMMAND.stringof~"."~sym~" must have 'SumType' type");

            static assert(getUDAs!(mem, SubCommandsUDA).length <= 1, "Member "~COMMAND.stringof~"."~sym~" has multiple 'SubCommands' UDAs");

            static foreach(TYPE; typeof(mem).Types)
                subCommands.add!(config, sym, TYPE, COMMAND);
        }
    }}

    return subCommands;
}