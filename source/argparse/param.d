module argparse.param;

import argparse.config;


struct Param(VALUE_TYPE)
{
    const Config* config;
    string name;

    static if(!is(VALUE_TYPE == void))
        VALUE_TYPE value;
}

alias RawParam = Param!(string[]);