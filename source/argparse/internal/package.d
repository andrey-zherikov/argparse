module argparse.internal;

import argparse : NamedArgument, TrailingArguments;
import argparse.api: Config, Result, Param, RawParam, RemoveDefault;
import argparse.internal.help;
import argparse.internal.command: Command;
import argparse.internal.lazystring;
import argparse.internal.arguments;
import argparse.internal.subcommands;
import argparse.internal.argumentuda;
import argparse.internal.hooks: Hook;
import argparse.internal.utils: formatAllowedValues;
import argparse.internal.enumhelpers: getEnumValues, getEnumValue;

import std.traits;
import std.sumtype: SumType, match;




///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/// Internal API
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package mixin template ForwardMemberFunction(string dest)
{
    import std.array: split;
    mixin("auto "~dest.split('.')[$-1]~"(Args...)(auto ref Args args) inout { import core.lifetime: forward; return "~dest~"(forward!args); }");
}

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

    CommandInfo info;

    Arguments arguments;

    ParseFunction!RECEIVER[] parseArguments;
    ParseFunction!RECEIVER[] completeArguments;

    alias void delegate(ref RECEIVER receiver, const Config* config) ParseFinalizer;
    ParseFinalizer[] parseFinalizers;


    mixin ForwardMemberFunction!"arguments.checkRestrictions";



    private void addArgument(alias symbol, alias uda)()
    {
        alias member = __traits(getMember, RECEIVER, symbol);

        static if(__traits(compiles, getUDAs!(typeof(member), Hook.ParsingDone)) && getUDAs!(typeof(member), Hook.ParsingDone).length > 0)
        {
            static foreach(hook; getUDAs!(typeof(member), Hook.ParsingDone))
                parseFinalizers ~= (ref RECEIVER receiver, const Config* config)
                    {
                        auto target = &__traits(getMember, receiver, symbol);
                        hook(*target, config);
                    };
        }

        addArgumentImpl!(symbol, uda, getUDAs!(member, Group));
    }

    private void addArgumentImpl(alias symbol, alias uda, groups...)()
    {
        static if(symbol is null)
            enum restrictions = [];
        else
            enum restrictions = getRestrictions!(RECEIVER, symbol);


        static assert(groups.length <= 1, "Member "~RECEIVER.stringof~"."~symbol~" has multiple 'Group' UDAs");
        static if(groups.length > 0)
            arguments.addArgument!(uda.info, restrictions, groups[0]);
        else
            arguments.addArgument!(uda.info, restrictions);

        static if(__traits(compiles, { parseArguments ~= uda.parsingFunc.getParseFunc!RECEIVER; }))
            parseArguments ~= uda.parsingFunc.getParseFunc!RECEIVER;
        else
            parseArguments ~= ParsingArgument!(symbol, uda, RECEIVER, false);

        completeArguments ~= ParsingArgument!(symbol, uda, RECEIVER, true);
    }
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


private void addArguments(Config config, COMMAND)(ref CommandArguments!COMMAND cmd)
{
    import std.sumtype: isSumType;

    enum isArgument(alias mem) = hasUDA!(mem, ArgumentUDA) ||
                                 hasUDA!(mem, NamedArgument) ||
                                 hasNoMembersWithUDA!COMMAND && !isOpFunction!mem && !isSumType!(typeof(mem));

    static foreach(sym; __traits(allMembers, COMMAND))
    {{
        alias mem = __traits(getMember, COMMAND, sym);

        // skip types
        static if(!is(mem) && isArgument!mem)
            cmd.addArgument!(sym, getMemberArgumentUDA!(config, COMMAND, sym, NamedArgument));
    }}
}

package auto commandArguments(Config config, COMMAND, CommandInfo info = getCommandInfo!(config, COMMAND))()
{
    checkArgumentName!COMMAND(config.namedArgChar);

    auto cmd = CommandArguments!COMMAND(info);

    addArguments!config(cmd);

    if(config.addHelp)
        cmd.addArgumentImpl!(null, getArgumentUDA!(Config.init, bool, null, HelpArgumentUDA()));

    return cmd;
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private template DefaultValueParseFunctions(T)
if(!is(T == void))
{
    import std.conv: to;

    static if(is(T == enum))
    {
        alias DefaultValueParseFunctions = ValueParseFunctions!(
            void,   // pre process
            Validators.ValueInList!(getEnumValues!T, typeof(RawParam.value)),   // pre validate
            getEnumValue!T,   // parse
            void,   // validate
            void,   // action
            void    // no-value action
        );
    }
    else static if(isSomeString!T || isNumeric!T)
    {
        alias DefaultValueParseFunctions = ValueParseFunctions!(
            void,   // pre process
            void,   // pre validate
            void,   // parse
            void,   // validate
            void,   // action
            void    // no-value action
        );
    }
    else static if(isBoolean!T)
    {
        alias DefaultValueParseFunctions = ValueParseFunctions!(
            void,                               // pre process
            void,                               // pre validate
            (string value)                      // parse
            {
                switch(value)
                {
                    case "":    goto case;
                    case "yes": goto case;
                    case "y":   return true;
                    case "no":  goto case;
                    case "n":   return false;
                    default:    return value.to!T;
                }
            },
            void,                               // validate
            void,                               // action
            (ref T result) { result = true; }   // no-value action
        );
    }
    else static if(isSomeChar!T)
    {
        alias DefaultValueParseFunctions = ValueParseFunctions!(
            void,                         // pre process
            void,                         // pre validate
            (string value)                // parse
            {
                return value.length > 0 ? value[0].to!T : T.init;
            },
            void,                         // validate
            void,                         // action
            void                          // no-value action
        );
    }
    else static if(isArray!T)
    {
        alias TElement = ForeachType!T;

        static if(!isArray!TElement || isSomeString!TElement)  // 1D array
        {
            static if(!isStaticArray!T)
                alias action = Actions.Append!T;
            else
                alias action = Actions.Assign!T;

            alias DefaultValueParseFunctions = DefaultValueParseFunctions!TElement
                .changePreProcess!splitValues
                .changeParse!((ref T receiver, RawParam param)
                {
                    static if(!isStaticArray!T)
                    {
                        if(receiver.length < param.value.length)
                            receiver.length = param.value.length;
                    }

                    foreach(i, value; param.value)
                    {
                        if(!DefaultValueParseFunctions!TElement.parse(receiver[i],
                        RawParam(param.config, param.name, [value])))
                            return false;
                    }

                    return true;
                })
                .changeAction!(action)
                .changeNoValueAction!((ref T param) {});
        }
        else static if(!isArray!(ForeachType!TElement) || isSomeString!(ForeachType!TElement))  // 2D array
        {
            alias DefaultValueParseFunctions = DefaultValueParseFunctions!TElement
                .changeAction!(Actions.Extend!TElement)
                .changeNoValueAction!((ref T param) { param ~= TElement.init; });
        }
        else
        {
            static assert(false, "Multi-dimentional arrays are not supported: " ~ T.stringof);
        }
    }
    else static if(isAssociativeArray!T)
    {
        import std.string : indexOf;
        alias DefaultValueParseFunctions = ValueParseFunctions!(
            splitValues,                                                // pre process
            void,                                                       // pre validate
            Parsers.PassThrough,                                        // parse
            void,                                                       // validate
            (ref T recepient, Param!(string[]) param)                   // action
            {
                alias K = KeyType!T;
                alias V = ValueType!T;

                foreach(input; param.value)
                {
                    auto j = indexOf(input, param.config.assignChar);
                    if(j < 0)
                        return false;

                    K key;
                    if(!DefaultValueParseFunctions!K.parse(key, RawParam(param.config, param.name, [input[0 .. j]])))
                        return false;

                    V value;
                    if(!DefaultValueParseFunctions!V.parse(value, RawParam(param.config, param.name, [input[j + 1 .. $]])))
                        return false;

                    recepient[key] = value;
                }
                return true;
            },
            (ref T param) {}    // no-value action
        );
    }
    else static if(is(T == function) || is(T == delegate) || is(typeof(*T) == function) || is(typeof(*T) == delegate))
    {
        alias DefaultValueParseFunctions = ValueParseFunctions!(
            void,                           // pre process
            void,                           // pre validate
            Parsers.PassThrough,            // parse
            void,                           // validate
            Actions.CallFunction!T,         // action
            Actions.CallFunctionNoParam!T   // no-value action
        );
    }
    else
    {
        alias DefaultValueParseFunctions = ValueParseFunctions!(
            void,   // pre process
            void,   // pre validate
            void,   // parse
            void,   // validate
            void,   // action
            void    // no-value action
        );
    }
}

unittest
{
    enum MyEnum { foo, bar, }

    import std.meta: AliasSeq;
    static foreach(T; AliasSeq!(string, bool, int, double, char, MyEnum))
        static foreach(R; AliasSeq!(T, T[], T[][]))
        {{
            // ensure that this compiles
            R receiver;
            Config config;
            DefaultValueParseFunctions!R.parse(receiver, RawParam(&config, "", [""]));
        }}
}

unittest
{
    alias test(R) = (string[][] values)
    {
        auto config = Config('=', ',');
        R receiver;
        foreach(value; values)
        {
            assert(DefaultValueParseFunctions!R.parse(receiver, RawParam(&config, "", value)));
        }
        return receiver;
    };

    static assert(test!(string[])([["1","2","3"], [], ["4"]]) == ["1","2","3","4"]);
    static assert(test!(string[][])([["1","2","3"], [], ["4"]]) == [["1","2","3"],[],["4"]]);

    static assert(test!(string[string])([["a=bar","b=foo"], [], ["b=baz","c=boo"]]) == ["a":"bar", "b":"baz", "c":"boo"]);

    static assert(test!(string[])([["1,2,3"], [], ["4"]]) == ["1","2","3","4"]);
    static assert(test!(string[string])([["a=bar,b=foo"], [], ["b=baz,c=boo"]]) == ["a":"bar", "b":"baz", "c":"boo"]);

    static assert(test!(int[])([["1","2","3"], [], ["4"]]) == [1,2,3,4]);
    static assert(test!(int[][])([["1","2","3"], [], ["4"]]) == [[1,2,3],[],[4]]);

}

unittest
{
    import std.math: isNaN;
    enum MyEnum { foo, bar, }

    alias test(T) = (string[] values)
    {
        T receiver;
        Config config;
        assert(DefaultValueParseFunctions!T.parse(receiver, RawParam(&config, "", values)));
        return receiver;
    };

    assert(test!string([""]) == "");
    assert(test!string(["foo"]) == "foo");
    assert(isNaN(test!double([""])));
    assert(test!double(["-12.34"]) == -12.34);
    assert(test!double(["12.34"]) == 12.34);
    assert(test!uint(["1234"]) == 1234);
    assert(test!int([""]) == int.init);
    assert(test!int(["-1234"]) == -1234);
    assert(test!char([""]) == char.init);
    assert(test!char(["f"]) == 'f');
    assert(test!bool([]) == true);
    assert(test!bool([""]) == true);
    assert(test!bool(["yes"]) == true);
    assert(test!bool(["y"]) == true);
    assert(test!bool(["true"]) == true);
    assert(test!bool(["no"]) == false);
    assert(test!bool(["n"]) == false);
    assert(test!bool(["false"]) == false);
    assert(test!MyEnum(["foo"]) == MyEnum.foo);
    assert(test!MyEnum(["bar"]) == MyEnum.bar);
    assert(test!(MyEnum[])(["bar","foo"]) == [MyEnum.bar, MyEnum.foo]);
    assert(test!(string[string])(["a=bar","b=foo"]) == ["a":"bar", "b":"foo"]);
    assert(test!(MyEnum[string])(["a=bar","b=foo"]) == ["a":MyEnum.bar, "b":MyEnum.foo]);
    assert(test!(int[MyEnum])(["bar=3","foo=5"]) == [MyEnum.bar:3, MyEnum.foo:5]);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) struct ValueParseFunctions(alias PreProcess,
                                             alias PreValidation,
                                             alias Parse,
                                             alias Validation,
                                             alias Action,
                                             alias NoValueAction)
{
    alias changePreProcess   (alias func) = ValueParseFunctions!(      func, PreValidation, Parse, Validation, Action, NoValueAction);
    alias changePreValidation(alias func) = ValueParseFunctions!(PreProcess,          func, Parse, Validation, Action, NoValueAction);
    alias changeParse        (alias func) = ValueParseFunctions!(PreProcess, PreValidation,  func, Validation, Action, NoValueAction);
    alias changeValidation   (alias func) = ValueParseFunctions!(PreProcess, PreValidation, Parse,       func, Action, NoValueAction);
    alias changeAction       (alias func) = ValueParseFunctions!(PreProcess, PreValidation, Parse, Validation,   func, NoValueAction);
    alias changeNoValueAction(alias func) = ValueParseFunctions!(PreProcess, PreValidation, Parse, Validation, Action,          func);

    template addDefaults(DefaultParseFunctions)
    {
        static if(is(PreProcess == void))
            alias preProc = DefaultParseFunctions;
        else
            alias preProc = DefaultParseFunctions.changePreProcess!PreProcess;

        static if(is(PreValidation == void))
            alias preVal = preProc;
        else
            alias preVal = preProc.changePreValidation!PreValidation;

        static if(is(Parse == void))
            alias parse = preVal;
        else
            alias parse = preVal.changeParse!Parse;

        static if(is(Validation == void))
            alias val = parse;
        else
            alias val = parse.changeValidation!Validation;

        static if(is(Action == void))
            alias action = val;
        else
            alias action = val.changeAction!Action;

        static if(is(NoValueAction == void))
            alias addDefaults = action;
        else
            alias addDefaults = action.changeNoValueAction!NoValueAction;
    }


    // Procedure to process (parse) the values to an argument of type T
    //  - if there is a value(s):
    //      - pre validate raw strings
    //      - parse raw strings
    //      - validate parsed values
    //      - action with values
    //  - if there is no value:
    //      - action if no value
    // Requirement: rawValues.length must be correct
    static Result parse(T)(ref T receiver, RawParam param)
    {
        return addDefaults!(DefaultValueParseFunctions!T).parseImpl(receiver, param);
    }
    static Result parseImpl(T)(ref T receiver, ref RawParam rawParam)
    {
        alias ParseType(T)     = .ParseType!(Parse, T);

        alias preValidation    = ValidateFunc!(PreValidation, string[], "Pre validation");
        alias parse(T)         = ParseFunc!(Parse, T);
        alias validation(T)    = ValidateFunc!(Validation, ParseType!T);
        alias action(T)        = ActionFunc!(Action, T, ParseType!T);
        alias noValueAction(T) = NoValueActionFunc!(NoValueAction, T);

        if(rawParam.value.length == 0)
        {
            return noValueAction!T(receiver, Param!void(rawParam.config, rawParam.name)) ? Result.Success : Result.Failure;
        }
        else
        {
            static if(!is(PreProcess == void))
                PreProcess(rawParam);

            Result res = preValidation(rawParam);
            if(!res)
                return res;

            auto parsedParam = Param!(ParseType!T)(rawParam.config, rawParam.name);

            if(!parse!T(parsedParam.value, rawParam))
                return Result.Failure;

            res = validation!T(parsedParam);
            if(!res)
                return res;

            if(!action!T(receiver, parsedParam))
                return Result.Failure;

            return Result.Success;
        }
    }
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
package(argparse) struct NoValueActionFunc(alias F, T)
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
                receiver = Parsers.Convert!T(value);
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
            Actions.Assign!(T, ParseType)(receiver, param.value);
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

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) struct Parsers
{
    static auto Convert(T)(string value)
    {
        import std.conv: to;
        return value.length > 0 ? value.to!T : T.init;
    }

    static auto PassThrough(string[] values)
    {
        return values;
    }
}

unittest
{
    assert(Parsers.Convert!int("7") == 7);
    assert(Parsers.Convert!string("7") == "7");
    assert(Parsers.Convert!char("7") == '7');

    assert(Parsers.PassThrough(["7","8"]) == ["7","8"]);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private struct Actions
{
    static auto Assign(DEST, SRC=DEST)(ref DEST param, SRC value)
    {
        param  = value;
    }

    static auto Append(T)(ref T param, T value)
    {
        param ~= value;
    }

    static auto Extend(T)(ref T[] param, T value)
    {
        param ~= value;
    }

    static auto CallFunction(F)(ref F func, RawParam param)
    {
        // ... func()
        static if(__traits(compiles, { func(); }))
        {
            func();
        }
        // ... func(string value)
        else static if(__traits(compiles, { func(param.value[0]); }))
        {
            foreach(value; param.value)
                func(value);
        }
        // ... func(string[] value)
        else static if(__traits(compiles, { func(param.value); }))
        {
            func(param.value);
        }
        // ... func(RawParam param)
        else static if(__traits(compiles, { func(param); }))
        {
            func(param);
        }
        else
            static assert(false, "Unsupported callback: " ~ F.stringof);
    }

    static auto CallFunctionNoParam(F)(ref F func, Param!void param)
    {
        // ... func()
        static if(__traits(compiles, { func(); }))
        {
            func();
        }
        // ... func(string value)
        else static if(__traits(compiles, { func(string.init); }))
        {
            func(string.init);
        }
        // ... func(string[] value)
        else static if(__traits(compiles, { func([]); }))
        {
            func([]);
        }
        // ... func(Param!void param)
        else static if(__traits(compiles, { func(param); }))
        {
            func(param);
        }
        // ... func(RawParam param)
        else static if(__traits(compiles, { func(RawParam.init); }))
        {
            func(RawParam(param.config, param.name));
        }
        else
            static assert(false, "Unsupported callback: " ~ F.stringof);
    }
}

unittest
{
    int i;
    Actions.Assign!(int)(i,7);
    assert(i == 7);
}

unittest
{
    int[] i;
    Actions.Append!(int[])(i,[1,2,3]);
    Actions.Append!(int[])(i,[7,8,9]);
    assert(i == [1,2,3,7,8,9]);

    alias test = (int[] v1, int[] v2) {
        int[] res;

        Param!(int[]) param;

        alias F = Actions.Append!(int[]);
        param.value = v1;   ActionFunc!(F, int[], int[])(res, param);

        param.value = v2;   ActionFunc!(F, int[], int[])(res, param);

        return res;
    };
    assert(test([1,2,3],[7,8,9]) == [1,2,3,7,8,9]);
}

unittest
{
    int[][] i;
    Actions.Extend!(int[])(i,[1,2,3]);
    Actions.Extend!(int[])(i,[7,8,9]);
    assert(i == [[1,2,3],[7,8,9]]);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) struct Validators
{
    template ValueInList(alias values, TYPE)
    {
        static auto ValueInList(Param!TYPE param)
        {
            import std.array : assocArray, join;
            import std.range : repeat, front;
            import std.conv: to;

            enum valuesAA = assocArray(values, false.repeat);
            enum allowedValues = values.to!(string[]).join(',');

            static if(is(typeof(values.front) == TYPE))
                auto paramValues = [param.value];
            else
                auto paramValues = param.value;

            foreach(value; paramValues)
                if(!(value in valuesAA))
                    return Result.Error("Invalid value '", value, "' for argument '", param.name, "'.\nValid argument values are: ", allowedValues);

            return Result.Success;
        }
        static auto ValueInList(Param!(TYPE[]) param)
        {
            foreach(ref value; param.value)
            {
                auto res = ValueInList!(values, TYPE)(Param!TYPE(param.config, param.name, value));
                if(!res)
                    return res;
            }
            return Result.Success;
        }
    }
}

unittest
{
    enum values = ["a","b","c"];
    Config config;

    assert(Validators.ValueInList!(values, string)(Param!string(&config, "", "b")));
    assert(!Validators.ValueInList!(values, string)(Param!string(&config, "", "d")));

    assert(Validators.ValueInList!(values, string)(RawParam(&config, "", ["b"])));
    assert(Validators.ValueInList!(values, string)(RawParam(&config, "", ["b","a"])));
    assert(!Validators.ValueInList!(values, string)(RawParam(&config, "", ["d"])));
    assert(!Validators.ValueInList!(values, string)(RawParam(&config, "", ["b","d"])));
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
