module argparse.internal.lazystring;

import std.sumtype: SumType, match;

package(argparse) struct LazyString
{
    SumType!(string, string function()) value;

    this(string s) { value = s; }
    this(string function() fn) { value = fn; }

    void opAssign(string s) { value = s; }
    void opAssign(string function() fn) { value = fn; }

    @property string get() const
    {
        return value.match!(
                (string _) => _,
                (string function() fn) => fn()
        );
    }

    bool isSet() const
    {
        return value.match!(
                (string s) => s.length > 0,
                (string function() fn) => fn != null
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
