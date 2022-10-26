module argparse.internal.lazystring;

import std.sumtype: SumType, match;

package(argparse) struct LazyString
{
    SumType!(string, string delegate()) value;

    this(string s) { value = s; }
    this(string delegate() dg) { value = dg; }

    void opAssign(string s) { value = s; }
    void opAssign(string delegate() dg) { value = dg; }

    @property string get() const
    {
        return value.match!(
                (string _) => _,
                (dg) => dg()
        );
    }

    bool isSet() const
    {
        return value.match!(
                (string s) => s.length > 0,
                (dg) => dg != null
        );
    }
}

unittest
{
    LazyString s;
    assert(!s.isSet());
    s = "asd";
    assert(s.isSet());
    assert(s.get == "asd");
    s = () => "qwe";
    assert(s.isSet());
    assert(s.get == "qwe");
    assert(LazyString("asd").get == "asd");
    assert(LazyString(() => "asd").get == "asd");
}
