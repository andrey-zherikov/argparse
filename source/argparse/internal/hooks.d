module argparse.internal.hooks;

package struct Hook
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
}