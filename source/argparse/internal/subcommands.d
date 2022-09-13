module argparse.internal.subcommands;

import argparse: Config, Result, Default;
import argparse.internal: CommandArguments, commandArguments, getCommandInfo;
import argparse.internal.parser: Parser;
import argparse.internal.lazystring;

import std.sumtype: match;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package enum DEFAULT_COMMAND = "";

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) struct CommandInfo
{
    string[] names = [""];
    LazyString usage;
    LazyString description;
    LazyString shortDescription;
    LazyString epilog;
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package alias InitSubCommandFunction (RECEIVER) = Result delegate(ref RECEIVER receiver);
package alias ParseSubCommandFunction(RECEIVER) = Result delegate(Config* config, ref Parser parser, const ref Parser.Argument arg, bool isDefaultCmd, ref RECEIVER receiver);

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


package struct SubCommands(RECEIVER)
{
    struct Handlers
    {
        InitSubCommandFunction !RECEIVER initialize;
        ParseSubCommandFunction!RECEIVER parse;
        ParseSubCommandFunction!RECEIVER complete;
    }

    uint level; // (sub-)command level, 0 = top level

    size_t[string] byName;

    CommandInfo[] info;
    Handlers[] handlers;


    auto length() const { return info.length; }

    void add(alias symbol, SUBCOMMAND, COMMAND)(string function(string str) convertCase, scope const CommandArguments!COMMAND* parentArguments)
    {
        enum defaultCommand = is(SUBCOMMAND == Default!COMMAND_TYPE, COMMAND_TYPE);
        static if(!defaultCommand)
            alias COMMAND_TYPE = SUBCOMMAND;

        //static assert(getUDAs!(member, Group).length <= 1,
        //    "Member "~COMMAND.stringof~"."~symbol~" has multiple 'Group' UDAs");

        //static if(getUDAs!(member, Group).length > 0)
        //    args.addArgument!(info, restrictions, getUDAs!(member, Group)[0])(ParsingArgument!(symbol, uda, info, COMMAND));
        //else
        //arguments.addSubCommand!(info);

        immutable index = length;

        enum cmdInfo = getCommandInfo!(COMMAND_TYPE, COMMAND_TYPE.stringof);

        static foreach(name; cmdInfo.names)
        {{
            auto n = convertCase(name);
            assert(!(n in byName), "Duplicated name of subcommand: "~n);
            byName[n] = index;
        }}

        static if(defaultCommand)
        {
            assert(!(DEFAULT_COMMAND in byName), "Multiple default subcommands: "~COMMAND.stringof~"."~symbol);
            byName[DEFAULT_COMMAND] = index;
        }

        info ~= cmdInfo;
        handlers ~= Handlers(
                ParsingSubCommandInit!(SUBCOMMAND, COMMAND, symbol),
                ParsingSubCommandArgument!(SUBCOMMAND, cmdInfo, COMMAND, symbol, false)(parentArguments),
                ParsingSubCommandArgument!(SUBCOMMAND, cmdInfo, COMMAND, symbol, true)(parentArguments)
            );
    }

    auto find(string name) const
    {
        struct Result
        {
            uint level = uint.max;
            InitSubCommandFunction !RECEIVER initialize;
            ParseSubCommandFunction!RECEIVER parse;
            ParseSubCommandFunction!RECEIVER complete;
        }

        auto p = name in byName;
        return !p ? Result.init : Result(level+1, handlers[*p].initialize, handlers[*p].parse, handlers[*p].complete);
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package auto ParsingSubCommandArgument(COMMAND_TYPE, CommandInfo info, RECEIVER, alias symbol, bool completionMode)(scope const CommandArguments!RECEIVER* parentArguments)
{
    return delegate(Config* config, ref Parser parser, const ref Parser.Argument arg, bool isDefaultCmd, ref RECEIVER receiver)
    {
        auto target = &__traits(getMember, receiver, symbol);

        alias parse = (ref COMMAND_TYPE cmdTarget)
        {
            static if(!is(COMMAND_TYPE == Default!TYPE, TYPE))
                alias TYPE = COMMAND_TYPE;

            auto command = commandArguments!(TYPE, info)(config, parentArguments);

            return parser.parse!completionMode(command, isDefaultCmd, cmdTarget, arg);
        };


        static if(typeof(*target).Types.length == 1)
            return (*target).match!parse;
        else
        {
            return (*target).match!(parse,
                (_)
                {
                    assert(false, "This should never happen");
                    return Result.Failure;
                }
            );
        }
    };
}

package alias ParsingSubCommandInit(COMMAND_TYPE, RECEIVER, alias symbol) =
    delegate(ref RECEIVER receiver)
    {
        auto target = &__traits(getMember, receiver, symbol);

        static if(typeof(*target).Types.length > 1)
            if((*target).match!((COMMAND_TYPE t) => false, _ => true))
                *target = COMMAND_TYPE.init;

        return Result.Success;
    };

