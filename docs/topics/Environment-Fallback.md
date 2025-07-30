# Fallback to environment variable

Arguments can be marked to fall back to environment variable if no value is provided on the command line. This allows to implement convenient fallback mechanisms (such as automatically picking up the username) or [12 Factor Apps](https://12factor.net/).

Example:

<code-block src="code_snippets/envfallback.d" lang="c++"/>
