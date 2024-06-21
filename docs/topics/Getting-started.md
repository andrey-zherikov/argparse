# Getting started

`argparse` provides User-Defined Attributes (UDA) that can be used to annotate `struct` members that are part of
command line interface.

## Without User-Defined Attributes

Using UDAs is not required and if a `struct` has no UDAs then all data members are treated as named command line
arguments:

<code-block src="../examples/getting_started/without_uda/app.d" lang="c++"/>

Running the program above with `-h` argument will have the following output:

<img src="hello_world_without_uda.png" alt="Hello world example" border-effect="rounded"/>

## With User-Defined Attributes

Although UDA-less approach is useful as a starting point, it's not enough for real command line tool:

<code-block src="../examples/getting_started/with_uda/app.d" lang="c++"/>

Running the program above with `-h` argument will have the following output:

<img src="hello_world_with_uda.png" alt="Hello world example" border-effect="rounded"/>
