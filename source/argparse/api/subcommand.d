module argparse.api.subcommand;


import std.sumtype: SumType, sumtype_match = match;
import std.meta;


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/// Default subcommand
public struct Default(COMMAND)
{
    COMMAND command;
    alias command this;
}

private enum isDefaultCommand(T) = is(T == Default!TYPE, TYPE);

private alias RemoveDefaultAttribute(T : Default!ORIG_TYPE, ORIG_TYPE) = ORIG_TYPE;
private alias RemoveDefaultAttribute(T) = T;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private struct None {}

public struct SubCommand(Commands...)
if(Commands.length > 0)
{
    private alias DefaultCommands = Filter!(isDefaultCommand, Commands);

    static assert(DefaultCommands.length <= 1, "Multiple default subcommands: "~DefaultCommands.stringof);

    static if(DefaultCommands.length > 0)
        package(argparse) alias DefaultCommand = RemoveDefaultAttribute!(DefaultCommands[0]);

    package(argparse) alias Types = staticMap!(RemoveDefaultAttribute, Commands);

    private SumType!(None, Types) impl;


    public this(T)(T value)
    if(staticIndexOf!(T, Types) >= 0)
    {
        impl = value;
    }


    public ref SubCommand opAssign(T)(T value)
    if(staticIndexOf!(T, Types) >= 0)
    {
        impl = value;
        return this;
    }


    public bool isSetTo(T)() const
    if(staticIndexOf!(T, Types) >= 0)
    {
        return impl.sumtype_match!((const ref T _) => true, (const ref _) => false);
    }

    public bool isSet() const
    {
        return impl.sumtype_match!((const ref None _) => false, (const ref _) => true);
    }
}


package(argparse) enum bool isSubCommand(T) = is(T : SubCommand!Args, Args...);


public template match(handlers...)
{
    auto ref match(Sub : const SubCommand!Args, Args...)(auto ref Sub sc)
    {
        alias RETURN_TYPE = typeof(SumType!(SubCommand!Args.Types).init.sumtype_match!handlers);

        static if(is(RETURN_TYPE == void))
            alias NoneHandler = (None _) {};
        else
            alias NoneHandler = (None _) => RETURN_TYPE.init;

        return sc.impl.sumtype_match!(NoneHandler, handlers);
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
    assert(sub.match!(_ => _.i) == 1);
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

        static assert(is(SUBCMD.impl.Types == AliasSeq!(None,A,B)));  // underlying types have no `Default`

        static assert(!SUBCMD.init.isSet);

        static foreach(CMD; AliasSeq!(A, B))
        {
            static assert(!SUBCMD.init.isSetTo!CMD);

            // can initialize with command
            static assert(SUBCMD(CMD.init).isSet);
            static assert(SUBCMD(CMD.init).isSetTo!CMD);

            {
                // can assign a command
                SUBCMD s;
                assert(!s.isSet);
                assert(s.match!(_ => _.i) == 0);

                s = CMD.init;
                assert(s.isSet);
                assert(s.isSetTo!CMD);

                // match without returning value
                s.match!((ref CMD _) { _.i = 123; },(_){});

                // match with returning value
                assert(s.match!(_ => _.i) == 123);
            }
        }
    }
}