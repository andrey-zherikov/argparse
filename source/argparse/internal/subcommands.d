module argparse.internal.subcommands;

import argparse.config;
import argparse.internal.commandinfo;


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package enum DEFAULT_COMMAND = "";

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


package struct SubCommands
{
    size_t[string] byName;

    CommandInfo[] info;


    void add(Config config, alias symbol, bool isDefault, CommandInfo cmdInfo)()
    {
        //static assert(getUDAs!(member, Group).length <= 1,
        //    "Member "~COMMAND.stringof~"."~symbol~" has multiple 'Group' UDAs");

        //static if(getUDAs!(member, Group).length > 0)
        //    args.addArgument!(info, restrictions, getUDAs!(member, Group)[0])(ParsingArgument!(symbol, uda, info, COMMAND));
        //else
        //arguments.addSubCommand!(info);

        immutable index = info.length;

        static foreach(name; cmdInfo.names)
        {{
            assert(!(name in byName), "Duplicated name of subcommand: "~name);
            byName[name] = index;
        }}

        static if(isDefault)
        {
            assert(!(DEFAULT_COMMAND in byName), "Multiple default subcommands: "~symbol);
            byName[DEFAULT_COMMAND] = index;
        }

        info ~= cmdInfo;
    }
}