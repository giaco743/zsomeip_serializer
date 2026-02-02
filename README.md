# SomeIP serialization in Zig

As Zig provides compile time reflection and has support for bit sized integers, it seems to be the perfect fit for SomeIP serialization and deserialization. This is my attempt at providing an implementation for SomeIP serialization and deserialization in Zig.

## Usage

SomeIP supports serialization of all primitive types and compound types like fixed and dynamic arrays, but also more complex compund types like structs and union.

```c
const MyStruct = struct {
    a: u8,
    b: u16,
    c: u32,
};
const MyUnion = union {
    a: u8,
    b: u16,
    c: u32,
};
```

The entry point for serialization is the generic `serialize` function, that uses compile time reflection to analyse the type passed to the function and to dispatch to the specialised serializer functions.

```c
const givenStruct = Test{
    .a = 0x12,
    .b = 0x3456,
    .c = 0x789ABCDE,
};
const expected = &[_]u8{ 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE };

var buffer = [_]u8{0} ** 1024;
var fba = std.heap.FixedBufferAllocator.init(&buffer);
var allocator = fba.allocator();
const slice = try allocator.alloc(u8, 100);
defer allocator.free(slice);

var serializer = zsip.Serializer.init(slice);
try zsip.serialize(zsip.Deployment{ .struct_depl = zsip.StructDeployment{} }, givenStruct, &serializer);
try std.testing.expectEqualSlices(u8, serializer.get(), expected);
```

## Deployment Parameters

SomeIP allows for customizing the serialization of a specific type according to deployment parameters. Deployment parameters are passed to the serialize function as the first parameter. There are different types of deployments applying to certain types:
* ArrayDeplyoment:
    - length width: u8, u16, u32
    - min
    - max
* StructDeployment:
    - FieldDeployments
* UnionDeployment:
    - length width
    - type width

The deployment has to match the provided type otherwise the call to `serialize` will return a `WrongDeployment` error.
