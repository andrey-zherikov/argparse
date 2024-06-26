# Restrict allowed values

In some cases an argument can receive one of the limited set of values. This can be achieved by adding `.AllowedValues!()`
to UDA:

<code-block src="code_snippets/allowed_values.d" lang="c++"/>

For the value that is not in the allowed list, this error will be printed:

<img src="allowed_values_error.png" alt="Allowed values error" border-effect="rounded"/>

> If the type of destination data member is `enum`, then the allowed values are automatically limited to those
> listed in the `enum`.
>
> See [Enum](Supported-types.md#enum) section for details.
>
{style="note"}