# Argument dependencies

## Mutually exclusive arguments {id="MutuallyExclusive"}

Mutually exclusive arguments (i.e., those that can’t be used together) can be declared using `MutuallyExclusive()` UDA:

<code-block src="code_snippets/mutually_exclusive.d" lang="c++"/>

> Parentheses `()` are required for this UDA to work correctly.
>
{style="warning"}

Set of mutually exclusive arguments can be marked as required in order to require exactly one of the arguments:

<code-block src="code_snippets/mutually_exclusive_required.d" lang="c++"/>


## Mutually required arguments {id="RequiredTogether"}

Mutually required arguments (i.e., those that require other arguments) can be declared using `RequiredTogether()` UDA:

<code-block src="code_snippets/mutually_required.d" lang="c++"/>

> Parentheses `()` are required for this UDA to work correctly.
>
{style="warning"}

Set of mutually required arguments can be marked as required in order to require all arguments:

<code-block src="code_snippets/mutually_required_required.d" lang="c++"/>
