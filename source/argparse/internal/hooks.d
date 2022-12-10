module argparse.internal.hooks;

import std.traits: getUDAs;

import argparse.api: Config;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private struct Hook
{
    struct ParsingDone(alias func)
    {
        static auto opCall(Args...)(auto ref Args args)
        {
            import core.lifetime: forward;
            return func(forward!args);
        }
    }
}

package(argparse) struct Hooks
{
    alias onParsingDone(alias func) = Hook.ParsingDone!func;

    alias ParsingDoneHandler(TYPE) = void delegate(ref TYPE receiver, const Config* config);
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private enum hookCall(TYPE, alias symbol, hook) = (ref TYPE receiver, const Config* config)
{
    auto target = &__traits(getMember, receiver, symbol);
    hook(*target, config);
};

package enum parsingDoneHandlers(TYPE, alias symbol) = {
    alias member = __traits(getMember, TYPE, symbol);

    Hooks.ParsingDoneHandler!TYPE[] handlers;

    static if(__traits(compiles, getUDAs!(typeof(member), Hook.ParsingDone)) && getUDAs!(typeof(member), Hook.ParsingDone).length > 0)
    {
        static foreach(hook; getUDAs!(typeof(member), Hook.ParsingDone))
            handlers ~= hookCall!(TYPE, symbol, hook);
    }

    return handlers;
}();