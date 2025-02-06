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
        return name.length > 0 && name[0] == config.namedArgPrefix;
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
