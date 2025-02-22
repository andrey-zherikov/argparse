# AllowedValues

`AllowedValues` UDA is used to list all values that an argument can accept. This is very useful in the cases when an argument
must have a value from a specific list, for example, when argument type is `enum`.

**Signature**

```C++
AllowedValues(string[] values...)
```

**Parameters**

- `values`

  Values that argument can have.

**Usage example**

```C++
enum Fruit {
    apple,
    @AllowedValues("no-apple","noapple")
    noapple
};
```
