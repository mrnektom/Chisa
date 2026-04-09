# chisa Language Specification

> Current version. Reflects what is implemented and functional in the compiler pipeline.

---

## Compilation Pipeline

```
.chisa source → Tokenizer → Parser → Analyzer → IRGen → LLVMCodeGen → native executable
```

### Compiler CLI

```bash
zig build run -- -i <file.chisa> -o <output>        # compile to native executable
zig build run -- -i <file.chisa> -r                 # JIT-run via MCJIT
zig build run -- -i <file.chisa> -dump-ir           # dump LLVM IR
zig build run -- -i <file.chisa> -dump-symbols      # dump all symbols as JSON
zig build run -- -i <file.chisa> -v                 # verbose: print compilation stages
```

---

## Comments

Comments are ignored by the compiler and may appear anywhere whitespace is allowed.

```chisa
// full-line comment
let x = 42   // trailing comment

/*
multi-line
block comment
*/

/// documentation comment for the next declaration
fn add(a: number, b: number): number = a + b

/**
 * multi-line documentation comment
 * for the next declaration
 */
struct Point { x: number, y: number }
```

### Line comments

Line comments begin with `//` and continue to the end of the current line.

### Block comments

Block comments begin with `/*` and end with `*/`. They may span multiple lines.

### Documentation comments

Documentation comments attach descriptive text to the declaration that immediately follows them.

- `///` starts a single-line documentation comment.
- `/** ... */` starts a block documentation comment.

### Constraints

- Comments do not affect program semantics.
- Documentation comments apply to the next declaration.
- Ordinary comments and documentation comments are distinct forms: `//` and `/* ... */` are non-documenting, while
  `///` and `/** ... */` are documenting.

---

## Variables

```chisa
let x: number = 42      // mutable variable
const name = "hello"    // constant
x = 100                 // reassignment
```

Type annotation is optional — the analyzer infers types where possible.

---

## Types

| Type         | Description                 |
|--------------|-----------------------------|
| `number`     | numeric                     |
| `boolean`    | boolean                     |
| `char`       | character                   |
| `long`       | 64-bit integer              |
| `short`      | 16-bit integer              |
| `byte`       | 8-bit integer               |
| `Unit`       | singleton unit type         |
| `T[]`        | array of T                  |
| `Pointer<T>` | pointer to T                |
| `SomeName`   | user-defined struct or enum |
| `Generic<T>` | instantiated generic type   |

### Scalar type declarations

Scalar (primitive) types are declared in stdlib using the `scalar` keyword:

```chisa
scalar number
scalar long
```

Valid scalar names: `number`, `long`, `short`, `byte`, `boolean`, `char`. Declaring an unknown name is a compile error.
`stdlib/prelude.chisa` declares all built-in scalar types, making them available in every module.

---

## Functions

```chisa
fn add(a: number, b: number): number = a + b

fn process<T>(value: T): T {
    return value    // generic identity function
}

external fn print(n: number): void   // provided by the host/runtime

export fn getTen(): number = 10      // visible to importing modules
```

- Parameters and return type can be annotated explicitly.
- Generic type parameters are declared with `<T, U, ...>`.
- `external` declares a function implemented outside chisa.
- `export` marks a function visible to other modules.
- Function overloading is supported (same name, different signatures).

---

## Extension Functions

Extension functions add methods to existing types without modifying the original type definition.

```chisa
fn number.double(): number = this * 2

fn number.clamp(min: number, max: number): number =
    if (this < min) min else if (this > max) max else this

fn string.isEmpty(): boolean = this.length == 0

fn Point.translate(dx: number, dy: number): Point =
    Point { x: this.x + dx, y: this.y + dy }

fn Point.distanceSq(other: Point): number {
    let dx = this.x - other.x
    let dy = this.y - other.y
    dx * dx + dy * dy
}
```

### Generic extensions

```chisa
fn Option<T>.getOrElse(default: T): T = match this {
    Option.Some(v) -> v,        // unwrap the present value
    Option.None    -> default   // fall back to the caller-provided default
}

fn Result<T, E>.isOk(): boolean = match this {
    Result.Ok(_)  -> true,      // ignore payload, only care about variant
    Result.Err(_) -> false
}
```

### Call syntax

```chisa
let n = 5
let d = n.double()               // 10
let c = n.clamp(0, 3)            // 3

let p = Point { x: 1, y: 2 }
let q = p.translate(3, 4)        // Point { x: 4, y: 6 }

let opt = Option.Some(42)
let v = opt.getOrElse(0)         // 42
```

- The receiver is the expression to the left of the dot; inside the body it is `this`.
- `expr.method(args)` is equivalent to calling `ReceiverType.method(expr, args)`.
- Extensions may be defined on any type: built-in scalars (`number`, `string`, `boolean`, `char`, `long`, `short`,
  `byte`), structs, enums, arrays, and generic instantiations.
- Dispatch is **static** — the extension to call is resolved at compile time based on the receiver's static type.
- `export` is supported: `export fn Point.translate(...)`.
- Overloading rules apply — the same extension name can be defined with different signatures on the same receiver type.
- Extensions do not have access to any private state beyond what is available through normal field access.

---

## Lambdas and Closures

Lambda expressions create anonymous function values.

In expression position, `{ ... }` is reserved for lambda syntax. Plain block expressions are not part of the language.

```chisa
let greet  = { -> "hello" }                         // no parameters
let double = { x -> x * 2 }                         // one param, type inferred
let add    = { a: number, b: number -> a + b }      // explicit parameter types
let thunk: () -> string = { "hello" }               // no parameters, `->` omitted in typed context
let inc:   (number) -> number = { it + 1 }          // single expected parameter is implicit `it`

// Block body — last expression is the return value
let compute = { x: number ->
    let tmp = x * x      // local inside the lambda body
    tmp + 1              // implicit return value
}
```

### Trailing lambda

When the last argument of a call is a lambda it can be placed outside the parentheses:

```chisa
list.map { x -> x * 2 }
list.map { it * 2 }
list.filter { x -> x > 0 }
list.fold(0) { acc, x -> acc + x }
```

### Lambda shorthand from expected type

If a lambda appears in a context with an expected function type, two shorthand forms are available:

- For `() -> R`, `{ expr }` is treated as a zero-argument lambda.
- For `(T) -> R`, the single parameter may be omitted and is implicitly available as `it`.

These shorthands are only valid when the expected function type is known from context. Without an expected function
type, `{ ... }` remains a normal block expression.

### Closures

Lambdas capture variables from the enclosing scope **by reference** — mutations are visible on both sides of the closure
boundary:

```chisa
let count = 0
let inc   = { -> count = count + 1 }   // mutates captured state

inc()
inc()
// count == 2
```

### Invocation

A stored function value is called with the same syntax as a named function:

```chisa
let result = add(3, 4)   // 7
```

---

## Functional Types

Function types are written as `(ParamType, ...) -> ReturnType`.

```chisa
let f:      (number) -> number  = { x -> x * 2 }
let pred:   (number) -> boolean = { x -> x > 0 }
let action: () -> void          = { -> print(42) }   // no parameters, no useful result
let lazy:   () -> number        = { 42 }
let next:   (number) -> number  = { it + 1 }
```

Function types are first-class — they can appear anywhere a type is expected: variable annotations, parameters, and
return types.

### Higher-order functions

```chisa
fn apply(f: (number) -> number, x: number): number = f(x)

fn makeAdder(n: number): (number) -> number = { x -> x + n }

let addFive = makeAdder(5)
let result  = addFive(3)    // 8
```

### Type aliases

`type` declares an alias for any type expression.

```chisa
type Predicate<T>    = (T) -> boolean
type Transform<A, B> = (A) -> B
type Action          = () -> void
```

Aliases are purely structural — `Predicate<number>` and `(number) -> boolean` are interchangeable. `export type` exports
an alias to other modules.

```chisa
fn filter<T>(arr: T[], pred: Predicate<T>): T[] = ...

export type Callback = (string) -> void
```

---

## Safe Navigation (`?.` Operator)

`?.` is syntactic sugar for calling `.map { v -> ... }` on an `Option<T>` value. It applies a field access, method call,
or extension call to the wrapped value only if it is `Some`, and propagates `None` otherwise.

### Syntax and desugaring

```chisa
opt?.field          // opt.map { v -> v.field }
opt?.method(args)   // opt.map { v -> v.method(args) }
opt?.ext(args)      // opt.map { v -> v.ext(args) }   (extension functions included)
```

The result type is always `Option<T>` where `T` is the type of the accessed field or the return type of the called
function.

### Examples

```chisa
struct Address { city: string }
struct User    { name: string, address: Option<Address> }   // nested option field

let user: Option<User> = Option.Some(User { name: "Alice", address: Option.Some(Address { city: "NY" }) })

let name: Option<string> = user?.name          // safe field read on Option<User>
let city: Option<string> = user?.address?.city // short-circuits to None at any missing step
```

Field access via regular `.` and safe access via `?.` can be mixed in the same chain:

```chisa
// address is Option<Address>, city is a plain string field on Address
let city = user?.address?.city   // Option<string>
```

### Extension calls

```chisa
fn string.upper(): string = ...

let name: Option<string> = Option.Some("alice")
let up: Option<string>   = name?.upper()   // Option.Some("ALICE")
```

### Chaining

`?.` is left-associative. Each step receives the `Option` produced by the previous step:

```chisa
// a: Option<A>,  b: B field on A,  c: C field on B
let val: Option<C> = a?.b?.c
// equivalent to: a.map { v -> v.b }.map { v -> v.c }
```

### Unwrapping the result

Combine with `getOrElse` (an extension on `Option<T>`) to extract a default value:

```chisa
let city: string = user?.address?.city.getOrElse("unknown")
```

### Constraints

- The receiver of `?.` must be `Option<T>`; applying it to any other type is a compile error.
- `?.` has lower precedence than `.`: `a.b?.c` means `(a.b)?.c`.

---

## `!!` Operator (Error Propagation)

`!!` is a postfix operator for propagating errors out of the current function. It either returns early (on `Left`) or
unwraps the value (on `Right`).

### Desugaring

When the operand is already `Either<L, R>`, `!!` matches it directly — no `.toEither()` call is made:

```chisa
eitherExpr!!
// expands to:
match eitherExpr {
    Either.Left(e)  -> return e,   // propagate the error immediately
    Either.Right(v) -> v           // continue with the unwrapped success value
}
```

When the operand is any other type, `.toEither()` is called first:

```chisa
expr!!
// expands to:
match expr.toEither() {
    Either.Left(e)  -> return e,   // convert-and-propagate failure
    Either.Right(v) -> v           // convert-and-unwrap success
}
```

The type of the whole `expr!!` expression is `Right`.

### Type constraints

- If the operand is not `Either`, it must have a `.toEither()` extension returning `Either<L, R>`.
- `L` must exactly match the declared return type of the enclosing function.
- `!!` may only appear inside a function body.

### Usage with `Either` directly

```chisa
fn divide(a: number, b: number): Either<string, number> =
    if (b == 0) Either.Left("division by zero") else Either.Right(a / b)

fn compute(): string {
    let result: number = divide(10, 2)!!   // exits early from compute() on Left
    result * 3                             // executed only after successful unwrap
}
```

### Usage with `Option`

`Option<T>` has a stdlib extension `fn Option<T>.toEither(): Either<Unit, T>`:

- `Option.None` → `Either.Left(Unit)`
- `Option.Some(v)` → `Either.Right(v)`

```chisa
fn findUser(id: number): Option<string> = ...

fn greet(): Unit {
    let name: string = findUser(42)!!   // Option<T>.toEither() maps None to Left(Unit)
    print(name)
}
```

### User-defined `toEither()`

Any type can participate in `!!` by defining a `toEither()` extension:

```chisa
enum ParseError { InvalidInput, Overflow }
struct ParseResult { value: number, error: Option<ParseError> }

fn ParseResult.toEither(): Either<ParseError, number> =
    match this.error {
        Option.Some(e) -> Either.Left(e),
        Option.None    -> Either.Right(this.value)
    }

fn run(): ParseError {
    let n: number = parseNumber("42")!!   // propagates ParseError on failure
    print(n)
}
```

---

## Structs

```chisa
struct Point { x: number, y: number }
struct Pair<T, U> { first: T, second: U }

let p = Point { x: 10, y: 20 }   // struct literal
let val = p.x                    // field read
p.x = 5                          // field write
```

- Fields are declared with explicit type annotations.
- Generic structs use `<T, U, ...>` parameter lists.
- Field access uses dot notation; chaining is supported (`a.b.c`).

---

## Enums

```chisa
enum Option<T> { Some(T), None }
enum Result<T, E> { Ok(T), Err(E) }

let x = Option.Some(42)   // variant constructor with payload
```

- Variants can carry a payload type: `Some(T)`.
- Variants without payload are simple names: `None`.
- Generic enums use `<T, ...>` parameter lists.

---

## Pattern Matching

`match` is an expression and returns a value. Arms have the form `Pattern -> expr`. The `else` arm is a wildcard that
matches anything.

### Primitives

```chisa
let result = match x {
    0    -> "zero",   // literal pattern
    1    -> "one",
    else -> "other"   // wildcard fallback
}
```

Supported for `number`, `boolean`, `char`, and `string` literals.

### Enums

```chisa
let result = match x {
    Option.Some(v) -> v + 1,   // bind payload to `v`
    Option.None    -> 0
}
```

Payload variables are bound in the arm body.

### Structs

```chisa
let result = match p {
    Point { x: 0, y } -> y,       // mix literal match and binding
    Point { x, y }    -> x + y    // bind both fields by name
}
```

Fields can be matched by value (`x: 0`) or simply bound as a variable (`y`). Unmentioned fields are ignored.

### Wildcard

```chisa
let result = match x {
    0    -> "zero",
    else -> "non-zero"
}
```

`else` must be the last arm. It binds no variable — use a preceding binding arm if the value is needed.

---

## Control Flow

### If

```chisa
let y = if (x > 0) x else 0

if (flag) {
    doSomething()   // executed when the condition is true
} else {
    doOther()       // executed otherwise
}
```

`if` is an expression — both branches must produce compatible types.

### While

```chisa
while (cond) {
    body
}
```

### For

```chisa
for (let i = 0; i < 10; i = i + 1) {
    if (i == 3) continue   // skip this iteration
    if (i == 7) break      // exit the loop entirely
    print(i)
}
```

### Return / Break / Continue

```chisa
return value
return
break
continue
```

---

## Operators

| Category          | Operators                                                       |
|-------------------|-----------------------------------------------------------------|
| Arithmetic        | `+` `-` `*` `/` `%`                                             |
| Comparison        | `==` `!=` `<` `>` `<=` `>=`                                     |
| Logical           | `&&` `\|\|` `!`                                                 |
| Error propagation | `!!` (postfix, see [!! Operator](#-operator-error-propagation)) |

---

## Arrays

```chisa
let arr = [1, 2, 3]
let v = arr[0]
arr[1] = 99
```

Array type is written as `number[]`. Index access supports chaining: `arr[i][j]`.

---

## Pointers

```chisa
let x = 42
let p = ptr(x)      // take the address of `x`
let y = deref(p)    // read the pointed-to value

let mem = alloc(4096)   // raw heap allocation
free(mem, 4096)         // caller must free manually
```

Pointer type is written as `Pointer<T>`. `ptr`, `deref`, `alloc`, and `free` are built-in operations.

---

## Inline Assembly

`asm { }` embeds raw assembly instructions directly inside a function body. Bindings explicitly map chisa values to
registers and back.

### Syntax

```chisa
asm {
    in  <reg> = <expr>    // input binding
    in  <reg> = <expr>
    out <reg> = <name>    // output binding — declares `let <name>` in current scope
    clobber <reg>, <reg>  // registers modified but not listed as outputs (optional)
    "<instruction>"       // assembly instruction strings, emitted in order
    "<instruction>"
}
```

All `in`, `out`, and `clobber` lines must appear before the instruction strings.

### Bindings

| Binding            | Meaning                                                                                                              |
|--------------------|----------------------------------------------------------------------------------------------------------------------|
| `in reg = expr`    | Evaluates `expr` and loads the result into `reg` before the instructions run                                         |
| `out reg = name`   | After the instructions, reads `reg` and declares `let name` in the enclosing scope                                   |
| `clobber reg, ...` | Declares registers that the asm modifies without an `out` binding; lets the compiler avoid placing live values there |

### Example — Linux syscalls

```chisa
// exit(0)
fn exit(): Unit {
    asm {
        in rax = 60   // Linux x86-64 syscall number for exit
        in rdi = 0    // exit status
        "syscall"     // transfer control to the kernel
    }
}

// write(fd, buf, len) → bytes written
fn write(fd: number, buf: Pointer<byte>, len: number): number {
    asm {
        in  rax = 1           // syscall number for write
        in  rdi = fd          // file descriptor
        in  rsi = buf         // buffer pointer
        in  rdx = len         // buffer length
        out rax = written     // kernel return value
        clobber rcx, r11      // registers overwritten by syscall
        "syscall"
    }
    written
}
```

### Constraints

- `asm` is a statement — it has no type and cannot be used as an expression.
- `asm` may only appear inside a function body.
- An `out` binding declares a new `let` variable; the name must not already exist in the current scope.
- The assembly dialect and register names are platform-defined (x86-64 by default).
- The compiler does not analyse or validate instruction strings — correctness is the programmer's responsibility.

---

## Conditional Compilation

Conditional compilation selects declarations, statements, or expressions at compile time based on the target platform or
user-defined flags. The keyword is `when`; conditions are compile-time predicates, not runtime expressions.

### File-level: `@target`

`@target` at the top of a file makes the entire file conditional. The file is included in the build only when the
condition is true.

```chisa
@target(os == "linux")

// everything below is compiled only when `os` is "linux"
fn exit(): Unit {
    asm {
        in rax = 60
        in rdi = 0
        "syscall"
    }
}
```

### Top-level `when`

`when` selects which top-level declarations to emit. Each arm contains a single declaration or a `{ }` block of
declarations.

```chisa
when {
    os == "linux" -> fn exit(): Unit {
        asm { in rax = 60; in rdi = 0; "syscall" }
    }
    os == "windows" -> fn exit(): Unit {
        ExitProcess(0)
    }
    else -> external fn exit(): Unit   // fallback for unsupported targets
}

// Multi-declaration arm
when {
    os == "linux" -> {
        fn exit(): Unit { ... }
        fn write(fd: number, buf: Pointer<byte>, len: number): number { ... }
    }
    else -> {
        external fn exit(): Unit
        external fn write(fd: number, buf: Pointer<byte>, len: number): number
    }
}
```

### Inside functions

`when` can also appear as a statement or expression inside a function body.

```chisa
// as expression
fn pageSize(): number = when {
    arch == "x86_64"  -> 4096,    // common page size on x86-64
    arch == "aarch64" -> 16384,
    else              -> 4096
}

// as statement
fn setup(): Unit {
    when {
        debug -> enableLogging()
        else  -> disableLogging()
    }
}
```

### Built-in compile-time variables

| Variable | Type   | Example values                                 |
|----------|--------|------------------------------------------------|
| `os`     | string | `"linux"`, `"windows"`, `"macos"`, `"freebsd"` |
| `arch`   | string | `"x86_64"`, `"aarch64"`, `"wasm32"`            |

### User-defined flags

Flags are passed to the compiler with `-D`:

```
chisa build -D debug -D profile=embedded src/main.chisa
```

Inside `when`, a boolean flag is referenced by name; a string flag uses `==`:

```chisa
when {
    debug                -> print("debug build")
    profile == "embedded" -> useStaticAlloc()
    else                 -> useHeapAlloc()
}
```

### Condition syntax

| Form                  | Meaning                                                    |
|-----------------------|------------------------------------------------------------|
| `variable == "value"` | String equality against a built-in variable or string flag |
| `flagname`            | True if `-D flagname` was passed                           |
| `!cond`               | Logical not                                                |
| `cond && cond`        | Logical and                                                |
| `cond \|\| cond`      | Logical or                                                 |

### Semantics

- Compile-time `when` is evaluated before type-checking. Non-matching arms are ignored completely — they are not
  type-checked and emit no code or declarations.
- `when` is syntactically distinct from runtime `match`: `match` requires an expression to match against; `when` uses
  bare conditions.
- If no arm matches and there is no `else`, nothing is emitted — this is not an error.
- `when` used as an expression inside a function requires all matching arms to produce compatible types (same rules as
  `if`).
- `@target` must appear before any declarations in a file; only one `@target` per file is allowed.

---

## Imports and Exports

```chisa
import { getTen, x as alias } from "./lib.chisa"
export { someFn } from "./other_lib.chisa"   // re-export from another module

export fn helper(): number = 1
export struct Point { x: number, y: number }
export enum Option<T> { Some(T), None }
```

- `import` supports named imports and `as` aliasing.
- `export` can be applied directly to declarations or used as a grouped statement.

---

## Standard Library

The standard library (`stdlib/`) is automatically available in every module via the prelude.

### `Option<T>`

```chisa
enum Option<T> { Some(T), None }
```

| Extension   | Signature                                     | Description                                   |
|-------------|-----------------------------------------------|-----------------------------------------------|
| `getOrElse` | `fn Option<T>.getOrElse(default: T): T`       | Returns the wrapped value or `default`        |
| `map`       | `fn Option<T>.map<U>(f: (T) -> U): Option<U>` | Applies `f` to the inner value if `Some`      |
| `toEither`  | `fn Option<T>.toEither(): Either<Unit, T>`    | `None` → `Left(Unit)`, `Some(v)` → `Right(v)` |

### `Either<Left, Right>`

```chisa
enum Either<Left, Right> { Left(Left), Right(Right) }
```

| Extension   | Signature                                                   | Description                                         |
|-------------|-------------------------------------------------------------|-----------------------------------------------------|
| `mapRight`  | `fn Either<L, R>.mapRight<R2>(f: (R) -> R2): Either<L, R2>` | Transforms the `Right` value, passes `Left` through |
| `getOrElse` | `fn Either<L, R>.getOrElse(default: R): R`                  | Returns the `Right` value or `default`              |

### `Unit`

`Unit` is a singleton type with exactly one value, also written `Unit`. Functions that produce no meaningful result have
return type `Unit`.

---

## Modifiers Summary

| Modifier   | Applies to                                    | Meaning                                    |
|------------|-----------------------------------------------|--------------------------------------------|
| `let`      | variable                                      | mutable binding                            |
| `const`    | variable                                      | immutable binding                          |
| `external` | function                                      | implemented outside chisa                  |
| `export`   | any top-level declaration, extension function | visible to other modules                   |
| `type`     | type alias declaration                        | names a type expression; supports generics |

---

## Known Limitations (current version)

### Language features

- **Type inference is partial and context-driven** — the analyzer infers types reliably for straightforward local
  expressions, direct calls, and generic constructions where the concrete type can be read from argument payloads or
  from an expected target type. Inference is much weaker when the only evidence is indirect.

  Works well when the type is visible directly:

  ```chisa
  let n = 42
  let ok = Option.Some(42)              // infers Option<number>
  let f: (number) -> number = { x -> x + 1 }
  ```

  Weakens when the result type must be reconstructed from several steps of generic flow:

  ```chisa
  let value =
      Option.Some(42)
          .map { x -> x + 1 }
          .map { y -> y.toString() }
  // May require an explicit type on `value` or on one of the lambdas.
  ```

- **Generic call inference depends on declared parameter shapes** — for generic functions and generic extension methods,
  type parameters are inferred by matching the declared parameter types against the actual argument types, and sometimes
  against the expected result type. If a type parameter appears only in a position the analyzer cannot use as evidence,
  monomorphization does not happen and the call must be written with explicit type arguments or stronger surrounding
  type annotations.

  Typical case that works:

  ```chisa
  fn wrap<T>(value: T): Option<T> = Option.Some(value)

  let a = wrap(42)                      // infers T = number
  ```

  Case that may need extra help because the type parameter is driven indirectly:

  ```chisa
  fn makeDefault<T>(f: () -> T): T = f()

  let x = makeDefault { -> 42 }         // usually OK
  let y = makeDefault { -> Option.None }
  // `T` may be impossible to infer here without an expected type.
  ```

  In practice this often means writing:

  ```chisa
  let y: Option<number> = makeDefault { -> Option.None }
  ```

- **Expected-type propagation is limited** — contextual typing is used in some places, such as typed higher-order
  parameters and expected enum result types, but it does not flow through every expression form. As a result, code that
  is theoretically inferable may still need an explicit variable type, function parameter type, or return type to
  compile.

  Example where the surrounding type gives the analyzer enough information:

  ```chisa
  let pred: (number) -> boolean = { x -> x > 0 }
  ```

  Equivalent code without the expected type may fail:

  ```chisa
  let pred = { x -> x > 0 }
  // `x` has no declared type and no expected function type to inherit from.
  ```

- **Generic enum constructors need contextual type information** — unit variants such as `Option.None` can instantiate
  a generic enum only when the surrounding expression already tells the analyzer which concrete enum type is expected.
  Without that context, the constructor has no payload from which to infer type arguments.

  Works when the expected type is present:

  ```chisa
  let value: Option<number> = Option.None
  ```

  Fails without the surrounding type:

  ```chisa
  let value = Option.None
  // compile error: cannot infer type arguments for generic enum
  ```

- **Standalone lambda parameters are not inferred** — a lambda parameter type is inferred only when the lambda appears
  in a context with an expected function type (for example, when passed to a typed higher-order function or assigned to
  a variable with a function type). Otherwise parameter annotations are required. In contexts with an expected
  zero-parameter function type, `{ ... }` is treated as a lambda body with no `->`. In contexts with an expected
  single-parameter function type, the parameter may be omitted entirely and is available as `it`.

  Works:

  ```chisa
  fn applyTwice(f: (number) -> number, x: number): number = f(f(x))
  fn runLater(f: () -> number): number = f()

  let result = applyTwice({ n -> n + 1 }, 10)
  // `n` is inferred as `number` from the declared parameter type of `applyTwice`.

  let result2 = applyTwice({ it + 1 }, 10)
  // `it` is implicitly introduced as the single expected lambda parameter.

  let result3 = runLater({ 42 })
  // the expected `() -> number` type makes the block expression an argument-less lambda.
  ```

  Does not work without annotation or context:

  ```chisa
  let inc = { n -> n + 1 }
  // compile error: cannot infer type of lambda parameter `n`
  ```

  Required workaround:

  ```chisa
  let inc = { n: number -> n + 1 }
  // or
  let inc: (number) -> number = { n -> n + 1 }
  ```

- **Nested higher-order and generic chains are the weakest case** — inference becomes fragile when lambdas, generic
  returns, extension chains, and propagated expected types all interact in the same expression. Breaking the expression
  into intermediate bindings with explicit types is often required.

  For example:

  ```chisa
  let result =
      users
          .map { user -> user.address }
          .map { address -> address.city }
          .getOrElse("unknown")
  ```

  This style may need to be rewritten as:

  ```chisa
  let addresses: Option<Address> = users.map { user: User -> user.address }
  let cities: Option<string> = addresses.map { address: Address -> address.city }
  let result = cities.getOrElse("unknown")
  ```

- **Inference failures are not always reported cleanly** — when the analyzer cannot resolve a type, diagnostics may
  still surface the internal placeholder `unknown` instead of a more specific user-facing type error.
- **`comptime { }` / `runtime { }` blocks are not implemented inside function bodies** — parser/tests reserve this
  syntax, but the current compiler does not analyze, execute, or lower these blocks yet.

### Design notes

- **No `null`** — by design. Use `Option<T>` and `?.` instead.
