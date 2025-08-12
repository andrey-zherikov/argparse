module argparse.api.subcommand;


import std.sumtype: SumType, sumtype_match = match;
import std.meta;
import std.typecons: Nullable;


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/// Default subcommand
public struct Default(COMMAND)
{
}

private enum isDefaultCommand(T) = is(T == Default!TYPE, TYPE);

private alias RemoveDefaultAttribute(T : Default!ORIG_TYPE, ORIG_TYPE) = ORIG_TYPE;
private alias RemoveDefaultAttribute(T) = T;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

public struct SubCommand(Commands...)
if(Commands.length > 0)
{
    private alias DefaultCommands = Filter!(isDefaultCommand, Commands);

    static assert(DefaultCommands.length <= 1, "Multiple default subcommands: "~DefaultCommands.stringof);

    static if(DefaultCommands.length > 0)
    {
        package(argparse) alias DefaultCommand = RemoveDefaultAttribute!(DefaultCommands[0]);

        package(argparse) alias Types = AliasSeq!(DefaultCommand, Filter!(templateNot!isDefaultCommand, Commands));

        private SumType!Types impl = DefaultCommand.init;
    }
    else
    {
        package(argparse) alias Types = Commands;

        private Nullable!(SumType!Types) impl;
    }

    public this(T)(T value)
    if(staticIndexOf!(T, Types) >= 0)
    {
        impl = SumType!Types(value);
    }


    public ref SubCommand opAssign(T)(T value)
    if(staticIndexOf!(T, Types) >= 0)
    {
        impl = SumType!Types(value);
        return this;
    }


    public bool isSetTo(T)() const
    if(staticIndexOf!(T, Types) >= 0)
    {
        if(!isSet())
            return false;

        static if(Types.length == 1)
            return true;
        else
            return this.matchCmd!((const ref T _) => true, (const ref _) => false);
    }

    public bool isSet() const
    {
        static if(is(DefaultCommand))
            return true;
        else
            return !impl.isNull;
    }
}


package(argparse) enum bool isSubCommand(T) = is(T : SubCommand!Args, Args...);


public template matchCmd(handlers...)
{
    auto ref matchCmd(Sub : const SubCommand!Args, Args...)(auto ref Sub sc)
    {
        static if(is(Sub.DefaultCommand))
            return sc.impl.sumtype_match!(handlers);
        else
        {
            if (!sc.impl.isNull)
                return sc.impl.get.sumtype_match!(handlers);
            else
            {
                alias RETURN_TYPE = typeof(sc.impl.get.init.sumtype_match!handlers);

                static if(!is(RETURN_TYPE == void))
                    return RETURN_TYPE.init;
            }
        }
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

unittest
{
    struct A
    {
        int i;
    }

    immutable sub = SubCommand!(A)(A(1));
    static assert(isSubCommand!(typeof(sub)));
    assert(sub.matchCmd!(_ => _.i) == 1);
}

unittest
{
    struct A { int i; }
    struct B { int i; }

    static assert(!__traits(compiles, SubCommand!()));
    static assert(!__traits(compiles, SubCommand!(A,A)));
    static assert(!__traits(compiles, SubCommand!(Default!A,Default!B)));

    static assert(!isSubCommand!(SumType!(A,B)));

    static foreach(SUBCMD; AliasSeq!(SubCommand!(A,B), SubCommand!(Default!A,B), SubCommand!(A,Default!B)))
    {
        static assert(isSubCommand!SUBCMD);

        static assert(Filter!(isDefaultCommand, SUBCMD.Types).length == 0);  // underlying types have no `Default`

        static if(is(SUBCMD.DefaultCommand))
            static assert(SUBCMD.init.isSet);
        else
            static assert(!SUBCMD.init.isSet);

        static foreach(CMD; AliasSeq!(A, B))
        {
            static if(is(SUBCMD.DefaultCommand == CMD))
                static assert(SUBCMD.init.isSetTo!CMD);
            else
                static assert(!SUBCMD.init.isSetTo!CMD);

            // can initialize with command
            static assert(SUBCMD(CMD.init).isSet);
            static assert(SUBCMD(CMD.init).isSetTo!CMD);

            {
                // can assign a command
                SUBCMD s;
                assert(s.matchCmd!(_ => _.i) == 0);

                s = CMD.init;
                assert(s.isSet);
                assert(s.isSetTo!CMD);

                // match without returning value
                s.matchCmd!((ref CMD _) { _.i = 123; },(_){});

                // match with returning value
                assert(s.matchCmd!(_ => _.i) == 123);
            }
        }
    }
}