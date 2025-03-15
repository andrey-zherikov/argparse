module argparse.param;

import argparse.config;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

struct Param(VALUE_TYPE)
{
    const(Config)* config;
    immutable string name;

    static if(!is(VALUE_TYPE == void))
        VALUE_TYPE value;

    package bool isNamedArg() const
    {
        import std.string: startsWith;
        return name.startsWith(config.shortNamePrefix) || name.startsWith(config.longNamePrefix);
    }
}

alias RawParam = Param!(string[]);

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

unittest
{
    Config config;
    RawParam p1;
    auto p2 = p1;
}

unittest
{
    Config config;
    assert(!RawParam(&config).isNamedArg);
    assert(!RawParam(&config,"a").isNamedArg);
    assert(RawParam(&config,"-a").isNamedArg);
}
