module argparse.internal.subcommands;

import argparse.internal.commandinfo;



///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


package struct SubCommands
{
    size_t[string] byName;

    CommandInfo[] info;


    void add(CommandInfo cmdInfo)()
    {
        immutable index = info.length;

        static foreach(name; cmdInfo.names)
        {{
            assert(!(name in byName), "Duplicated name of subcommand: "~name);
            byName[name] = index;
        }}

        info ~= cmdInfo;
    }
}