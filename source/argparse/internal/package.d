module argparse.internal;

import argparse : NamedArgument;
import argparse.config;
import argparse.internal.help: HelpArgumentUDA;
import argparse.internal.arguments: Arguments;
import argparse.internal.subcommands: CommandInfo, getCommandInfo;
import argparse.internal.argumentuda: ArgumentUDA, getMemberArgumentUDA, getArgumentUDA;

import std.traits;


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/// Internal API
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private auto checkDuplicates(alias sortedRange, string errorMsg)() {
    static if(sortedRange.length >= 2)
    {
        enum value = {
            import std.conv : to;

            foreach(i; 1..sortedRange.length-1)
                if(sortedRange[i-1] == sortedRange[i])
                    return sortedRange[i].to!string;

            return "";
        }();
        static assert(value.length == 0, errorMsg ~ value);
    }

    return true;
}

package bool checkArgumentNames(T)()
{
    enum names = {
        import std.algorithm : sort;

        string[] names;
        static foreach (sym; getSymbolsByUDA!(T, ArgumentUDA))
        {{
            enum argUDA = getUDAs!(__traits(getMember, T, __traits(identifier, sym)), ArgumentUDA)[0];

            static assert(!argUDA.info.positional || argUDA.info.names.length <= 1,
            "Positional argument should have exactly one name: "~T.stringof~"."~sym.stringof);

            static foreach (name; argUDA.info.names)
            {
                static assert(name.length > 0, "Argument name can't be empty: "~T.stringof~"."~sym.stringof);

                names ~= name;
            }
        }}

        return names.sort;
    }();

    return checkDuplicates!(names, "Argument name appears more than once: ");
}

private void checkArgumentName(T)(char namedArgChar)
{
    import std.exception: enforce;

    static foreach(sym; getSymbolsByUDA!(T, ArgumentUDA))
        static foreach(name; getUDAs!(__traits(getMember, T, __traits(identifier, sym)), ArgumentUDA)[0].info.names)
            enforce(name[0] != namedArgChar, "Name of argument should not begin with '"~namedArgChar~"': "~name);
}

package bool checkPositionalIndexes(T)()
{
    import std.conv  : to;
    import std.range : lockstep, iota;


    enum positions = () {
        import std.algorithm : sort;

        uint[] positions;
        static foreach (sym; getSymbolsByUDA!(T, ArgumentUDA))
        {{
            enum argUDA = getUDAs!(__traits(getMember, T, __traits(identifier, sym)), ArgumentUDA)[0];

            static if (argUDA.info.positional)
                positions ~= argUDA.info.position.get;
        }}

        return positions.sort;
    }();

    if(!checkDuplicates!(positions, "Positional arguments have duplicated position: "))
        return false;

    static foreach (i, pos; lockstep(iota(0, positions.length), positions))
        static assert(i == pos, "Positional arguments have missed position: " ~ i.to!string);

    return true;
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package struct CommandArguments(RECEIVER)
{
    private enum _validate = checkArgumentNames!RECEIVER && checkPositionalIndexes!RECEIVER;

    Arguments arguments;
}


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package enum hasNoMembersWithUDA(COMMAND) = getSymbolsByUDA!(COMMAND, ArgumentUDA  ).length == 0 &&
                                            getSymbolsByUDA!(COMMAND, NamedArgument).length == 0 &&
                                            getSymbolsByUDA!(COMMAND, argparse.SubCommands  ).length == 0;

package enum isOpFunction(alias mem) = is(typeof(mem) == function) && __traits(identifier, mem).length > 2 && __traits(identifier, mem)[0..2] == "op";


package template iterateArguments(TYPE)
{
    import std.meta: Filter;
    import std.sumtype: isSumType;

    template filter(alias sym)
    {
        alias mem = __traits(getMember, TYPE, sym);

        enum filter = !is(mem) && (
            hasUDA!(mem, ArgumentUDA) ||
            hasUDA!(mem, NamedArgument) ||
            hasNoMembersWithUDA!TYPE && !isOpFunction!mem && !isSumType!(typeof(mem)));
    }

    alias iterateArguments = Filter!(filter, __traits(allMembers, TYPE));
}

package auto commandArguments(Config config, COMMAND, CommandInfo info = getCommandInfo!(config, COMMAND))()
{
    checkArgumentName!COMMAND(config.namedArgChar);

    CommandArguments!COMMAND cmd;

    static foreach(symbol; iterateArguments!COMMAND)
    {{
        enum uda = getMemberArgumentUDA!(config, COMMAND, symbol, NamedArgument);

        cmd.arguments.addArgument!(COMMAND, symbol, uda.info);
    }}

    static if(config.addHelp)
    {
        enum uda = getArgumentUDA!(Config.init, bool, null, HelpArgumentUDA());

        cmd.arguments.addArgument!(COMMAND, null, uda.info);
    }

    return cmd;
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
