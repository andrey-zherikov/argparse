module argparse.internal.booleanhelpers;

import argparse.result;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

package(argparse) enum isBooleanFlag(T) =
    is(T == bool) ||
    is(T == R function(), R) ||
    is(T == R delegate(), R) ||
    is(T == R function(bool), R) ||
    is(T == R delegate(bool), R);

unittest
{
    assert(isBooleanFlag!bool);

    assert(!isBooleanFlag!int);
    assert(!isBooleanFlag!float);
    assert(!isBooleanFlag!string);
    assert(!isBooleanFlag!(int[]));
}

unittest
{
    import std.meta;
    static foreach(R; AliasSeq!(void, Result, int, int[], string, float))
    {
        static foreach(T; AliasSeq!(
            R function(),
            R delegate(),
            R function(bool),
            R delegate(bool),
        ))
            assert(isBooleanFlag!T);

        static foreach(P; AliasSeq!(int, int[], string, float))
            static foreach(T; AliasSeq!(
                R function(P),
                R delegate(P),
            ))
                assert(!isBooleanFlag!T);
    }
}