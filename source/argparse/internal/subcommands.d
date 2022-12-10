module argparse.internal.subcommands;

import argparse.api: Config, Result, RemoveDefault, isDefault;
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

private alias CreateSubCommandFunction(RECEIVER) = Parser.Command delegate(ref RECEIVER receiver);

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

        enum cmdInfo = getCommandInfo!(config, RemoveDefault!SUBCOMMAND, RemoveDefault!SUBCOMMAND.stringof);

        static foreach(name; cmdInfo.names)
        {{
            assert(!(name in byName), "Duplicated name of subcommand: "~name);
            byName[name] = index;
        }}

        static if(isDefault!SUBCOMMAND)
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
    return delegate(ref RECEIVER receiver)
    {
        auto target = &__traits(getMember, receiver, symbol);

        alias create = (ref COMMAND_TYPE actualTarget)
            => Parser.Command.create!(config, RemoveDefault!COMMAND_TYPE, info)(actualTarget);

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
                    return Parser.Command.init;
                }
            );
        }
    };
}