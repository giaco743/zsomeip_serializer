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
const MyUnion = union(enum) {
    a: u8,
    b: u16,
    c: u32,
};
```

The entry point for serialization is the generic `serialize` function, that uses compile time reflection to analyse the type passed to the function and to dispatch to the specialised serializer functions.

```c
    const Test = struct {
        a: u8,
        b: u16,
        c: u32,
    };
    const given = Test{
        .a = 0x12,
        .b = 0x3456,
        .c = 0x789ABCDE,
    };

    var buffer = [_]u8{0} ** 1024;

    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    var allocator = fba.allocator();

    const slice = try allocator.alloc(u8, 100);
    defer allocator.free(slice);
    const size = try zsip.serialize(given, slice[0..]);

    const deserialized = try zsip.deserialize(Test, allocator, slice[0..size]);
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

## Proxys and Stubs

Stubs and proxys for a specific service can be defined, by providing method definitions:

```rust
pub const method_def = [_]protocol.MethodDef{
    .{
        .In = Test,
        .Out = Test,
        .method_id = 5678,
        .name = "testF",
    },
    .{
        .In = void,
        .Out = void,
        .method_id = 6666,
        .name = "voidF",
    },
    .{
        .In = u16,
        .Out = u32,
        .method_id = 6969,
        .name = "intF",
    },

    .{
        .In = []const u8,
        .Out = []const u8,
        .method_id = 1000,
        .name = "greet",
    },
};
```

Stub handlers can be connected via:

```rust
const stubImpl = stub.handleRequests(&method_def, .{
    .testF = handleTest,
    .voidF = handleVoid,
    .intF = handleInteger,
    .greet = handleGreet,
});
stubImpl(&conn.stream, gpa.allocator());
```

For the proxy we can just pass the method definitions:

```rust
const myProxy = proxy.makeProxyMethods(service.method_def[0..]);
const response = try myProxy.testF(&proxy, request);
```
