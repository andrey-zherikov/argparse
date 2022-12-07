module argparse.internal.subcommands;

import argparse: Default;
import argparse.api: Config, Result;
import argparse.internal: commandArguments;
import argparse.internal.parser: Parser;
import argparse.internal.lazystring;
import argparse.internal.arguments;

import std.sumtype: match;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package enum DEFAULT_COMMAND = "";

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) struct CommandInfo
{
    string[] names = [""];
    string[] displayNames;
    LazyString usage;
    LazyString description;
    LazyString shortDescription;
    LazyString epilog;
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package template getCommandInfo(Config config, COMMAND, string name = "")
{
    auto finalize(alias initUDA)()
    {
        auto uda = initUDA;

        uda.displayNames = uda.names;

        static if(!config.caseSensitive)
        {
            import std.algorithm: each;
            uda.names.each!((ref _) => _ = config.convertCase(_));
        }

        return uda;
    }

    import std.traits: getUDAs;

    enum udas = getUDAs!(COMMAND, CommandInfo);
    static assert(udas.length <= 1, COMMAND.stringof~" has more that one @Command UDA");

    static if(udas.length > 0)
        enum getCommandInfo = finalize!(udas[0]);
    else
        enum getCommandInfo = finalize!(CommandInfo([name]));

    static assert(name == "" || getCommandInfo.names.length > 0 && getCommandInfo.names[0].length > 0, "Command "~COMMAND.stringof~" must have name");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private alias InitSubCommandFunction (RECEIVER) = Result delegate(ref RECEIVER receiver);
private alias ParseSubCommandFunction(RECEIVER) = Result delegate(ref Parser parser, const Parser.Command[] cmdStack, const ref Parser.Argument arg, ref RECEIVER receiver);
private alias CreateSubCommandFunction(RECEIVER) = Parser.Command delegate(ref RECEIVER receiver);

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


package struct SubCommands(RECEIVER)
{
    struct Handlers
    {
        InitSubCommandFunction !RECEIVER initialize;
        ParseSubCommandFunction!RECEIVER parse;
        ParseSubCommandFunction!RECEIVER complete;
        CreateSubCommandFunction!RECEIVER createCommand;
    }

    size_t[string] byName;

    CommandInfo[] info;
    Handlers[] handlers;


    auto length() const { return info.length; }

    void add(Config config, alias symbol, SUBCOMMAND, COMMAND)()
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

        enum cmdInfo = getCommandInfo!(config, COMMAND_TYPE, COMMAND_TYPE.stringof);

        static foreach(name; cmdInfo.names)
        {{
            assert(!(name in byName), "Duplicated name of subcommand: "~name);
            byName[name] = index;
        }}

        static if(defaultCommand)
        {
            assert(!(DEFAULT_COMMAND in byName), "Multiple default subcommands: "~COMMAND.stringof~"."~symbol);
            byName[DEFAULT_COMMAND] = index;
        }

        info ~= cmdInfo;
        handlers ~= Handlers(
                ParsingSubCommandInit!(SUBCOMMAND, COMMAND, symbol),
                ParsingSubCommandArgument!(config, SUBCOMMAND, cmdInfo, COMMAND, symbol, false),
                ParsingSubCommandArgument!(config, SUBCOMMAND, cmdInfo, COMMAND, symbol, true),
                ParsingSubCommandCreate!(config, SUBCOMMAND, cmdInfo, COMMAND, symbol),
            );
    }

    auto find(string name) const
    {
        struct Result
        {
            InitSubCommandFunction !RECEIVER initialize;
            ParseSubCommandFunction!RECEIVER parse;
            ParseSubCommandFunction!RECEIVER complete;
            CreateSubCommandFunction!RECEIVER createCommand;
        }

        auto p = name in byName;
        return !p ? Result.init : Result(handlers[*p].initialize, handlers[*p].parse, handlers[*p].complete, handlers[*p].createCommand);
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package auto ParsingSubCommandCreate(Config config, COMMAND_TYPE, CommandInfo info, RECEIVER, alias symbol)()
{
    return delegate(ref RECEIVER receiver)
    {
        auto target = &__traits(getMember, receiver, symbol);

        static if(!is(COMMAND_TYPE == Default!TYPE, TYPE))
            alias TYPE = COMMAND_TYPE;

        auto commandArgs = commandArguments!(config, TYPE, info);

        alias parse = (ref COMMAND_TYPE cmdTarget)
        {
            auto command = Parser.Command.create!config(commandArgs, cmdTarget);
            return command;
        };


        static if(typeof(*target).Types.length == 1)
            auto command = (*target).match!parse;
        else
        {
            auto command = (*target).match!(parse,
                (_)
            {
                assert(false, "This should never happen");
                //return Result.Failure;
                return Parser.Command.init;
            }
            );
        }
        return command;
    };
}

private auto ParsingSubCommandArgument(Config config, COMMAND_TYPE, CommandInfo info, RECEIVER, alias symbol, bool completionMode)()
{
    return delegate(ref Parser parser, const Parser.Command[] cmdStack, const ref Parser.Argument arg, ref RECEIVER receiver)
    {
        auto target = &__traits(getMember, receiver, symbol);

        static if(!is(COMMAND_TYPE == Default!TYPE, TYPE))
            alias TYPE = COMMAND_TYPE;

        auto commandArgs = commandArguments!(config, TYPE, info);

        alias parse = (ref COMMAND_TYPE cmdTarget)
        {
            auto command = Parser.Command.create!config(commandArgs, cmdTarget);
            return command;
            //return parser.parse!completionMode(command, arg);
        };


        static if(typeof(*target).Types.length == 1)
            auto command = (*target).match!parse;
        else
        {
            auto command = (*target).match!(parse,
                (_)
                {
                    assert(false, "This should never happen");
                    //return Result.Failure;
                    return Parser.Command.init;
                }
            );
        }

        return parser.parse!completionMode(cmdStack, command, arg);
        //return parser.parse!completionMode(command, arg);
        //return command;
    };
}

private alias ParsingSubCommandInit(COMMAND_TYPE, RECEIVER, alias symbol) =
    delegate(ref RECEIVER receiver)
    {
        auto target = &__traits(getMember, receiver, symbol);

        static if(typeof(*target).Types.length > 1)
            if((*target).match!((COMMAND_TYPE t) => false, _ => true))
                *target = COMMAND_TYPE.init;

        return Result.Success;
    };

