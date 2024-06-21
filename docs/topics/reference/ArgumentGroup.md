# ArgumentGroup

`ArgumentGroup` UDA is used to group arguments on help screen.

## Usage

**Signature**
```C++
ArgumentGroup(string name)
```

**Usage example**

```C++
@ArgumentGroup("my group")
{
...
}
```


## Public members

### Description

`Description` is used to add description text to a group.

**Signature**

```C++
... Description(auto ref ... group, string text)
... Description(auto ref ... group, string function() text)
```

**Parameters**

- `text`

  Text that contains group description or a function that returns such text.

**Usage example**

```C++
@(ArgumentGroup("my group").Description("custom description"))
{
...
}
```
