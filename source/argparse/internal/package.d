module argparse.internal;

import argparse.api.argument: NamedArgument;
import argparse.api.command: SubCommands;
import argparse.internal.argumentuda: ArgumentUDA;

import std.traits;


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/// Internal API
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//
//private auto checkDuplicates(alias sortedRange, string errorMsg)() {
//    static if(sortedRange.length >= 2)
//    {
//        enum value = {
//            import std.conv : to;
//
//            foreach(i; 1..sortedRange.length-1)
//                if(sortedRange[i-1] == sortedRange[i])
//                    return sortedRange[i].to!string;
//
//            return "";
//        }();
//        static assert(value.length == 0, errorMsg ~ value);
//    }
//
//    return true;
//}
//
//package bool checkPositionalIndexes(T)()
//{
//    import std.conv  : to;
//    import std.range : lockstep, iota;
//
//
//    enum positions = () {
//        import std.algorithm : sort;
//
//        uint[] positions;
//        static foreach (sym; getSymbolsByUDA!(T, ArgumentUDA))
//        {{
//            enum argUDA = getUDAs!(__traits(getMember, T, __traits(identifier, sym)), ArgumentUDA)[0];
//
//            static if (argUDA.info.positional)
//                positions ~= argUDA.info.position.get;
//        }}
//
//        return positions.sort;
//    }();
//
//    if(!checkDuplicates!(positions, "Positional arguments have duplicated position: "))
//        return false;
//
//    static foreach (i, pos; lockstep(iota(0, positions.length), positions))
//        static assert(i == pos, "Positional arguments have missed position: " ~ i.to!string);
//
//    return true;
//}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package enum hasNoMembersWithUDA(COMMAND) = getSymbolsByUDA!(COMMAND, ArgumentUDA  ).length == 0 &&
                                            getSymbolsByUDA!(COMMAND, NamedArgument).length == 0 &&
                                            getSymbolsByUDA!(COMMAND, SubCommands  ).length == 0;

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
