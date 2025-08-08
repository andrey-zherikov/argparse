module argparse.internal.calldispatcher;

import std.traits;


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

struct CallDispatcher(HANDLER)
{
    alias getFirstParameter(T) = Parameters!T[0];
    alias TYPES = staticMap!(getFirstParameter, typeof(__traits(getOverloads, HANDLER, "opCall")));

    union {
        static foreach(i, T; TYPES)
            mixin("T value_", i, ";");
    }

    size_t selection = -1;

    static foreach(i, T; TYPES)
    {
        this(T f)
        {
            mixin("value_",i) = f;
            selection = i;
        }
    }

    bool opCast(T : bool)() const
    {
        return selection != -1;
    }

    auto opCall(Args...)(auto ref Args args) const
    {
        import core.lifetime: forward;

        static foreach(i; 0 .. TYPES.length)
            if(i == selection)
                return HANDLER(mixin("value_",i), forward!args);

        assert(false);
    }
}

unittest
{
    struct Handler
    {
        static string[] opCall(string function(int) f, string v) { return ["int", f(0), v]; }
        static string[] opCall(string function(string) f, string v) { return ["string", f(""), v]; }
    }

    assert(CallDispatcher!Handler((int) => "foo")("boo") == ["int","foo","boo"]);
    assert(CallDispatcher!Handler((string _) => "woo")("doo") == ["string","woo","doo"]);
}