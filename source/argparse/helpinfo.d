module argparse.helpinfo;

import std.algorithm.iteration;
import std.typecons: Nullable;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


public struct ArgumentHelpInfo
{
    const string[] shortNames;
    const string[] longNames;

    string description;
    string placeholder;

    // Default value of an argument that should be printed on help screen; null if it should not be printed
    Nullable!string defaultValue;

    bool multipleOccurrence;
    bool optionalValue;
    bool optionalArgument;
    bool positional;
    bool hidden;
    bool booleanFlag;
}

public struct ArgumentGroupHelpInfo
{
    string name;
    string description;
    const size_t[] argIndex;
}

public struct SubCommandHelpInfo
{
    const string[] names;
    string description;

    bool isDefault;
}

public struct CommandHelpInfo
{
    string name;
    string usage;
    string description;
    string epilog;

    ArgumentHelpInfo[] arguments;

    ArgumentGroupHelpInfo[] userGroups;
    ArgumentGroupHelpInfo requiredGroup;
    ArgumentGroupHelpInfo optionalGroup;

    SubCommandHelpInfo[] subCommands;

    auto namedArguments() const
    {
        return arguments.filter!((ref _) => !_.hidden && !_.positional);
    }
    auto positionalArguments() const
    {
        return arguments.filter!((ref _) => !_.hidden && _.positional);
    }
}
