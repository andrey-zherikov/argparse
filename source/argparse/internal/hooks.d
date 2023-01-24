module argparse.internal.hooks;

import std.traits: getUDAs;

import argparse.config;

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

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

private enum hookCall(TYPE, alias symbol, hook) = (ref TYPE receiver, const Config* config)
{
    auto target = &__traits(getMember, receiver, symbol);
    hook(*target, config);
};

private auto parsingDoneHandlers(TYPE, symbols...)()
{
    void delegate(ref TYPE, const Config*)[] handlers;

    static foreach(symbol; symbols)
    {{
        alias member = __traits(getMember, TYPE, symbol);

        static if(__traits(compiles, getUDAs!(typeof(member), Hook.ParsingDone)) && getUDAs!(typeof(member), Hook.ParsingDone).length > 0)
        {
            static foreach(hook; getUDAs!(typeof(member), Hook.ParsingDone))
                handlers ~= hookCall!(TYPE, symbol, hook);
        }
    }}

    return handlers;
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) struct Hooks
{
    alias onParsingDone(alias func) = Hook.ParsingDone!func;

    package template Handlers(TYPE, symbols...)
    {
        enum parsingDone = parsingDoneHandlers!(TYPE, symbols);
    }
}

package struct HookHandlers
{
    private void delegate(const Config* config)[] parsingDone;


    void bind(TYPE, symbols...)(ref TYPE receiver)
    {
        static foreach(handler; parsingDoneHandlers!(TYPE, symbols))
            parsingDone ~= (const Config* config) => handler(receiver, config);
    }

    void onParsingDone(const Config* config) const
    {
        foreach(dg; parsingDone)
            dg(config);
    }
}
