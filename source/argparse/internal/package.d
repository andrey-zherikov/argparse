module argparse.internal;

import argparse : NamedArgument, TrailingArguments;
import argparse.config;
import argparse.result;
import argparse.param;
import argparse.api: RemoveDefault;
import argparse.internal.parsehelpers;
import argparse.internal.help;
import argparse.internal.command: Command;
import argparse.internal.lazystring;
import argparse.internal.arguments;
import argparse.internal.subcommands;
import argparse.internal.argumentuda;
import argparse.internal.utils: formatAllowedValues;
import argparse.internal.enumhelpers: getEnumValues, getEnumValue;

import std.traits;
import std.sumtype: SumType, match;




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

package alias ParseFunction(RECEIVER) = Result delegate(const Command[] cmdStack, Config* config, ref RECEIVER receiver, string argName, string[] rawValues);

package alias ParsingArgument(alias symbol, alias uda, RECEIVER, bool completionMode) =
    delegate(const Command[] cmdStack, Config* config, ref RECEIVER receiver, string argName, string[] rawValues)
    {
        static if(completionMode)
        {
            return Result.Success;
        }
        else
        {
            try
            {
                auto res = uda.info.checkValuesCount(argName, rawValues.length);
                if(!res)
                    return res;

                auto param = RawParam(config, argName, rawValues);

                auto target = &__traits(getMember, receiver, symbol);

                static if(is(typeof(target) == function) || is(typeof(target) == delegate))
                    return uda.parsingFunc.parse(target, param);
                else
                    return uda.parsingFunc.parse(*target, param);
            }
            catch(Exception e)
            {
                return Result.Error(argName, ": ", e.msg);
            }
        }
    };

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

// values => bool
// bool validate(T value)
// bool validate(T[i] value)
// bool validate(Param!T param)
// Result validate(T value)
// Result validate(T[i] value)
// Result validate(Param!T param)
private struct ValidateFunc(alias F, T, string funcName="Validation")
{
    static Result opCall(Param!T param)
    {
        static if(is(F == void))
        {
            return Result.Success;
        }
        else static if(__traits(compiles, { Result res = F(param); }))
        {
            // Result validate(Param!T param)
            return F(param);
        }
        else static if(__traits(compiles, { F(param); }))
        {
            // bool validate(Param!T param)
            return F(param) ? Result.Success : Result.Failure;
        }
        else static if(__traits(compiles, { Result res = F(param.value); }))
        {
            // Result validate(T values)
            return F(param.value);
        }
        else static if(__traits(compiles, { F(param.value); }))
        {
            // bool validate(T values)
            return F(param.value) ? Result.Success : Result.Failure;
        }
        else static if(__traits(compiles, { Result res = F(param.value[0]); }))
        {
            // Result validate(T[i] value)
            foreach(value; param.value)
            {
                Result res = F(value);
                if(!res)
                    return res;
            }
            return Result.Success;
        }
        else static if(__traits(compiles, { F(param.value[0]); }))
        {
            // bool validate(T[i] value)
            foreach(value; param.value)
                if(!F(value))
                    return Result.Failure;
            return Result.Success;
        }
        else
            static assert(false, funcName~" function is not supported for type "~T.stringof~": "~typeof(F).stringof);
    }
}

unittest
{
    auto test(alias F, T)(T[] values)
    {
        Param!(T[]) param;
        param.value = values;
        return ValidateFunc!(F, T[])(param);
    }

    // bool validate(T[] values)
    static assert(test!((string[] a) => true, string)(["1","2","3"]));
    static assert(test!((int[] a) => true, int)([1,2,3]));

    // bool validate(T value)
    static assert(test!((string a) => true, string)(["1","2","3"]));
    static assert(test!((int a) => true, int)([1,2,3]));

    // bool validate(Param!T param)
    static assert(test!((RawParam p) => true, string)(["1","2","3"]));
    static assert(test!((Param!(int[]) p) => true, int)([1,2,3]));
}

unittest
{
    auto test(alias F, T)()
    {
        Config config;
        return ValidateFunc!(F, T)(RawParam(&config, "", ["1","2","3"]));
    }
    static assert(test!(void, string[]));

    static assert(!__traits(compiles, { test!(() {}, string[]); }));
    static assert(!__traits(compiles, { test!((int,int) {}, string[]); }));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// => receiver + bool
// DEST action()
// bool action(ref DEST receiver)
// void action(ref DEST receiver)
// bool action(ref DEST receiver, Param!void param)
// void action(ref DEST receiver, Param!void param)
package struct NoValueActionFunc(alias F, T)
{
    static bool opCall(ref T receiver, Param!void param)
    {
        static if(is(F == void))
        {
            assert(false, "No-value action function is not provided");
        }
        else static if(__traits(compiles, { receiver = cast(T) F(); }))
        {
            // DEST action()
            receiver = cast(T) F();
            return true;
        }
        else static if(__traits(compiles, { F(receiver); }))
        {
            static if(__traits(compiles, { auto res = cast(bool) F(receiver); }))
            {
                // bool action(ref DEST receiver)
                return cast(bool) F(receiver);
            }
            else
            {
                // void action(ref DEST receiver)
                F(receiver);
                return true;
            }
        }
        else static if(__traits(compiles, { F(receiver, param); }))
        {
            static if(__traits(compiles, { auto res = cast(bool) F(receiver, param); }))
            {
                // bool action(ref DEST receiver, Param!void param)
                return cast(bool) F(receiver, param);
            }
            else
            {
                // void action(ref DEST receiver, Param!void param)
                F(receiver, param);
                return true;
            }
        }
        else
            static assert(false, "No-value action function has too many parameters: "~Parameters!F.stringof);
    }
}

unittest
{
    auto test(alias F, T)()
    {
        T receiver;
        assert(NoValueActionFunc!(F, T)(receiver, Param!void.init));
        return receiver;
    }

    static assert(!__traits(compiles, { NoValueActionFunc!(() {}, int); }));
    static assert(!__traits(compiles, { NoValueActionFunc!((int) {}, int); }));
    static assert(!__traits(compiles, { NoValueActionFunc!((int,int) {}, int); }));
    static assert(!__traits(compiles, { NoValueActionFunc!((int,int,int) {}, int); }));

    // DEST action()
    static assert(test!(() => 7, int) == 7);

    // bool action(ref DEST param)
    static assert(test!((ref int p) { p=7; return true; }, int) == 7);

    // void action(ref DEST param)
    static assert(test!((ref int p) { p=7; }, int) == 7);

    // bool action(ref DEST receiver, Param!void param)
    static assert(test!((ref int r, Param!void p) { r=7; return true; }, int) == 7);

    // void action(ref DEST receiver, Param!void param)
    static assert(test!((ref int r, Param!void p) { r=7; }, int) == 7);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private template ParseType(alias F, T)
{
    import std.traits : Unqual;

    static if(is(F == void))
        alias ParseType = Unqual!T;
    else static if(Parameters!F.length == 0)
        static assert(false, "Parse function should take at least one parameter");
    else static if(Parameters!F.length == 1)
    {
        // T action(arg)
        alias ParseType = Unqual!(ReturnType!F);
        static assert(!is(ParseType == void), "Parse function should return value");
    }
    else static if(Parameters!F.length == 2 && is(Parameters!F[0] == Config))
    {
        // T action(Config config, arg)
        alias ParseType = Unqual!(ReturnType!F);
        static assert(!is(ParseType == void), "Parse function should return value");
    }
    else static if(Parameters!F.length == 2)
    {
        // ... action(ref T param, arg)
        alias ParseType = Parameters!F[0];
    }
    else static if(Parameters!F.length == 3)
    {
        // ... action(Config config, ref T param, arg)
        alias ParseType = Parameters!F[1];
    }
    else static if(Parameters!F.length == 4)
    {
        // ... action(Config config, string argName, ref T param, arg)
        alias ParseType = Parameters!F[2];
    }
    else
        static assert(false, "Parse function has too many parameters: "~Parameters!F.stringof);
}

unittest
{
    static assert(is(ParseType!(void, double) == double));
    static assert(!__traits(compiles, { ParseType!((){}, double) p; }));
    static assert(!__traits(compiles, { ParseType!((int,int,int,int,int){}, double) p; }));

    // T action(arg)
    static assert(is(ParseType!((int)=>3, double) == int));
    static assert(!__traits(compiles, { ParseType!((int){}, double) p; }));
    // T action(Config config, arg)
    static assert(is(ParseType!((Config config, int)=>3, double) == int));
    static assert(!__traits(compiles, { ParseType!((Config config, int){}, double) p; }));
    // ... action(ref T param, arg)
    static assert(is(ParseType!((ref int, string v) {}, double) == int));
    // ... action(Config config, ref T param, arg)
    static assert(is(ParseType!((Config config, ref int, string v) {}, double) == int));
    // ... action(Config config, string argName, ref T param, arg)
    //static assert(is(ParseType!((Config config, string argName, ref int, string v) {}, double) == int));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// T parse(string[] values)
// T parse(string value)
// T parse(RawParam param)
// bool parse(ref T receiver, RawParam param)
// void parse(ref T receiver, RawParam param)
private struct ParseFunc(alias F, T)
{
    alias ParseType = .ParseType!(F, T);

    static bool opCall(ref ParseType receiver, RawParam param)
    {
        static if(is(F == void))
        {
            foreach(value; param.value)
                receiver = Convert!T(value);
            return true;
        }
        // T parse(string[] values)
        else static if(__traits(compiles, { receiver = cast(ParseType) F(param.value); }))
        {
            receiver = cast(ParseType) F(param.value);
            return true;
        }
        // T parse(string value)
        else static if(__traits(compiles, { receiver = cast(ParseType) F(param.value[0]); }))
        {
            foreach(value; param.value)
                receiver = cast(ParseType) F(value);
            return true;
        }
        // T parse(RawParam param)
        else static if(__traits(compiles, { receiver = cast(ParseType) F(param); }))
        {
            receiver = cast(ParseType) F(param);
            return true;
        }
        // bool parse(ref T receiver, RawParam param)
        // void parse(ref T receiver, RawParam param)
        else static if(__traits(compiles, { F(receiver, param); }))
        {
            static if(__traits(compiles, { auto res = cast(bool) F(receiver, param); }))
            {
                // bool parse(ref T receiver, RawParam param)
                return cast(bool) F(receiver, param);
            }
            else
            {
                // void parse(ref T receiver, RawParam param)
                F(receiver, param);
                return true;
            }
        }
        else
            static assert(false, "Parse function is not supported");
    }
}

unittest
{
    int i;
    RawParam param;
    param.value = ["1","2","3"];
    assert(ParseFunc!(void, int)(i, param));
    assert(i == 3);
}

unittest
{
    auto test(alias F, T)(string[] values)
    {
        T value;
        RawParam param;
        param.value = values;
        assert(ParseFunc!(F, T)(value, param));
        return value;
    }

    // T parse(string value)
    static assert(test!((string a) => a, string)(["1","2","3"]) == "3");

    // T parse(string[] values)
    static assert(test!((string[] a) => a, string[])(["1","2","3"]) == ["1","2","3"]);

    // T parse(RawParam param)
    static assert(test!((RawParam p) => p.value[0], string)(["1","2","3"]) == "1");

    // bool parse(ref T receiver, RawParam param)
    static assert(test!((ref string[] r, RawParam p) { r = p.value; return true; }, string[])(["1","2","3"]) == ["1","2","3"]);

    // void parse(ref T receiver, RawParam param)
    static assert(test!((ref string[] r, RawParam p) { r = p.value; }, string[])(["1","2","3"]) == ["1","2","3"]);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// bool action(ref T receiver, ParseType value)
// void action(ref T receiver, ParseType value)
// bool action(ref T receiver, Param!ParseType param)
// void action(ref T receiver, Param!ParseType param)
private struct ActionFunc(alias F, T, ParseType)
{
    static bool opCall(ref T receiver, Param!ParseType param)
    {
        static if(is(F == void))
        {
            Assign!(T, ParseType)(receiver, param.value);
            return true;
        }
        // bool action(ref T receiver, ParseType value)
        // void action(ref T receiver, ParseType value)
        else static if(__traits(compiles, { F(receiver, param.value); }))
        {
            static if(__traits(compiles, { auto res = cast(bool) F(receiver, param.value); }))
            {
                // bool action(ref T receiver, ParseType value)
                return cast(bool) F(receiver, param.value);
            }
            else
            {
                // void action(ref T receiver, ParseType value)
                F(receiver, param.value);
                return true;
            }
        }
        // bool action(ref T receiver, Param!ParseType param)
        // void action(ref T receiver, Param!ParseType param)
        else static if(__traits(compiles, { F(receiver, param); }))
        {
            static if(__traits(compiles, { auto res = cast(bool) F(receiver, param); }))
            {
                // bool action(ref T receiver, Param!ParseType param)
                return cast(bool) F(receiver, param);
            }
            else
            {
                // void action(ref T receiver, Param!ParseType param)
                F(receiver, param);
                return true;
            }
        }
        else
            static assert(false, "Action function is not supported");
    }
}

unittest
{
    auto param(T)(T values)
    {
        Param!T param;
        param.value = values;
        return param;
    }
    auto test(alias F, T)(T values)
    {
        T receiver;
        assert(ActionFunc!(F, T, T)(receiver, param(values)));
        return receiver;
    }

    assert(test!(void, string[])(["1","2","3"]) == ["1","2","3"]);

    static assert(!__traits(compiles, { test!(() {}, string[])(["1","2","3"]); }));
    static assert(!__traits(compiles, { test!((int,int) {}, string[])(["1","2","3"]); }));

    // bool action(ref T receiver, ParseType value)
    assert(test!((ref string[] p, string[] a) { p=a; return true; }, string[])(["1","2","3"]) == ["1","2","3"]);

    // void action(ref T receiver, ParseType value)
    assert(test!((ref string[] p, string[] a) { p=a; }, string[])(["1","2","3"]) == ["1","2","3"]);

    // bool action(ref T receiver, Param!ParseType param)
    assert(test!((ref string[] p, Param!(string[]) a) { p=a.value; return true; }, string[]) (["1","2","3"]) == ["1","2","3"]);

    // void action(ref T receiver, Param!ParseType param)
    assert(test!((ref string[] p, Param!(string[]) a) { p=a.value; }, string[])(["1","2","3"]) == ["1","2","3"]);
}

unittest
{
    alias test = (int[] v1, int[] v2) {
        int[] res;

        Param!(int[]) param;

        alias F = Append!(int[]);
        param.value = v1;   ActionFunc!(F, int[], int[])(res, param);

        param.value = v2;   ActionFunc!(F, int[], int[])(res, param);

        return res;
    };
    assert(test([1,2,3],[7,8,9]) == [1,2,3,7,8,9]);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private void splitValues(ref RawParam param)
{
    if(param.config.arraySep == char.init)
        return;

    import std.array : array, split;
    import std.algorithm : map, joiner;

    param.value = param.value.map!((string s) => s.split(param.config.arraySep)).joiner.array;
}

unittest
{
    alias test = (char arraySep, string[] values)
    {
        Config config;
        config.arraySep = arraySep;

        auto param = RawParam(&config, "", values);

        splitValues(param);

        return param.value;
    };

    static assert(test(',', []) == []);
    static assert(test(',', ["a","b","c"]) == ["a","b","c"]);
    static assert(test(',', ["a,b","c","d,e,f"]) == ["a","b","c","d","e","f"]);
    static assert(test(' ', ["a,b","c","d,e,f"]) == ["a,b","c","d,e,f"]);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
