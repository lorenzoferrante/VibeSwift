# Bitrig’s Swift Interpreter: From Code to Bytecode
[Bitrig](https://apps.apple.com/us/app/bitrig/id6747835910) dynamically generates and runs Swift apps on your phone. Normally this would require compiling and signing with Xcode, and you can’t do that on an iPhone.

To make it possible to instantly run your app, we built a Swift interpreter. But it’s an unusual interpreter, since it interprets from Swift… to Swift. One of the top questions we’ve gotten is how it’s implemented, so we wanted to share more about how it works.

Welcome to Part 2 in our series about how we built Bitrig's Swift interpreter. [In Part 1](https://bitrig.com/blog/swift-interpreter), we talked about the high-level idea: interpreting Swift from Swift itself, and how we can dynamically bridge into existing APIs. But how do we actually go from a Swift file on disk to something runnable inside our interpreter?

The short answer: we build our own bytecode.

Bytecode and the techniques we're using aren't novel in the world of interpreters. But they were new to us and it was not obvious exactly how to build such a system in Swift for Swift code. If you're curious to learn how we did it, then read on!

* * *

From Source to Structure
------------------------

The syntax tree that we get from SwiftSyntax includes mainly three types of elements: [declarations](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/declarations), [statements](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/statements), and [expressions](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/expressions). If you'd like a refresher on the details, check out the links. But in short:

*   **Declarations** define things like types, functions, and variables.
*   **Statements** describe what happens, step by step.
*   **Expressions** are the pieces of code that actually produce values.

Declarations are what we start with, since those are the outer-most types within a Swift code document. They give us the types and functions we need, but they don’t actually _do_ anything on their own. To actually start running some code, we have to take a function and interpret the array of statements that it contains.

To run those statements, we could walk the SwiftSyntax tree directly, but that can be slow and memory-intensive. Instead, we start by translating all of those statements into a compact intermediate bytecode.

[Bytecode](https://en.wikipedia.org/wiki/Bytecode) is just a stream of byte-sized instructions. Instead of a big, heterogeneous tree with dozens of node types, we get a flat, efficient representation that the interpreter can quickly step through.

We generate our bytecode by doing a light-weight compile of the syntax tree, where we make a runtime representation of each declaration. This representation includes an array of bytecode values for each function or computed variable it contains.

* * *

Generating Bytecode from Statements
-----------------------------------

Let’s explore how we map statements to bytecode. To start, we'll create an `Operation` type that represents the different types of operations we'll need the interpreter to support. These will be close to, but not 1-to-1 with, the Swift language. We can start with a few of the simpler statement types like `break` and `continue`. We'll encode each as a single byte:

```

enum Operation: UInt8 {
    case `break`
    case `continue`
    ...
}

```


Our bytecode will need additional data besides just the operations themselves (e.g. the arguments to the operations), so let's introduce a more general type for the bytecode itself:

```

struct Bytecode: RawRepresentable {
    var rawValue: UInt8

    init(_ operation: Operation) {
        rawValue = operation.rawValue
    }

    init(_ value: UInt8) {
        rawValue = value
    }
}

```


Then we can add a method to go from a SwiftSyntax statement to creating bytecode:

```

extension StmtSyntax {
    func appendBytecode(_ bytecode: inout [Bytecode]) {
        if kind == .breakStmt {
            bytecode.append(Bytecode(.break))
        } else if kind == .continueStmt {
            bytecode.append(Bytecode(.continue))
        } else if let statement = self.as(ExpressionStmtSyntax.self) {
            statement.expression.appendBytecode(&bytecode)
        ...
        }
    }
}

```


Now we can create bytecode from a function by pulling out its body's statements:

```

func createBytecode(function: FunctionDeclSyntax) -> [Bytecode] {
    var bytecode: [Bytecode] = []
    let statements = function.body?.statements
    statements?.appendBytecode(&bytecode)
    return bytecode
}

```


When the interpreter runs, it can just loop over the bytecode and switch on each operation type, which we'll examine in a bit.

* * *

Expressions
-----------

Statements are the necessary structure, but expressions are where the real action happens. Every Swift program boils down to evaluating expressions: literals, operations, function calls, member accesses, and so on. So next, we'll discuss converting expressions into bytecode.

Let’s start with the simplest expressions: literals.

An integer literal like `42` can be represented directly in the bytecode. A byte can easily represent a number, as a `UInt8`. To be able to represent the full 64-bit space of integer values, we'll need to combine together 8 of these `UInt8`s to represent all of the necessary bits. Since this means we'll need multiple bytes, we can't express this as an initializer on `Bytecode`, so instead we'll make an append-style method on arrays of `Bytecode`:

```

extension [Bytecode] {
    mutating func appendUInt64(_ value: UInt64) {
        // Represent the value in 8 bytes worth:
        append(Bytecode(rawValue: UInt8((value >> 56) & 0xFF)))
        append(Bytecode(rawValue: UInt8((value >> 48) & 0xFF)))
        append(Bytecode(rawValue: UInt8((value >> 40) & 0xFF)))
        append(Bytecode(rawValue: UInt8((value >> 32) & 0xFF)))
        append(Bytecode(rawValue: UInt8((value >> 24) & 0xFF)))
        append(Bytecode(rawValue: UInt8((value >> 16) & 0xFF)))
        append(Bytecode(rawValue: UInt8((value >> 8) & 0xFF)))
        append(Bytecode(rawValue: UInt8(value & 0xFF)))
    }
}

```


(Note: It's possible to optimize this more for common small integers by representing small integers within a single byte.)

With the ability to write a full 64-bit value, we can easily write `Int`s and `Double`s into the bytecode array by just converting them into a `UInt64`:

```

extension [Bytecode] {
    mutating func appendInt(_ value: Int) {
        appendUInt64(UInt64(bitPattern: Int64(value)))
    }

    mutating func appendDouble(_ value: Double) {
        appendFullUInt64(value.bitPattern)
    }
}

```


With that, we have all the pieces we need to create the representations for some literal types:

```

extension ExprSyntax {
    func appendBytecode(_ bytecode: inout [Bytecode]) {
        if kind == .nilLiteralExpr {
            bytecode.append(Bytecode(.nilLiteral))
        } else if let value = self.as(IntegerLiteralExprSyntax.self) {
            let number = Int(value.literal.text) ?? 0
            bytecode.append(Bytecode(.integerLiteral))
            bytecode.appendInt(value)
        } else if let value = self.as(FloatLiteralExprSyntax.self) {
            let number = Double(value.literal.text) ?? 0.0
            bytecode.append(Bytecode(.doubleLiteral))
            bytecode.appendDouble(number)
        }
    }
}

```


* * *

Interpreting the Bytecode
-------------------------

Now that we have our elements built up, we can write a basic interpreter to process them. First, we'll create the interpreter type itself, which will contain an array of bytecode to interpret. Then, we'll incorporate a program counter that tells us where in the bytecode we are. Finally, we'll make a stack where we can push and pop values:

```

struct Interpreter {
    let bytecode: [Bytecode]
    private var pc = 0
    private var valueStack: [InterpreterValue] = []
}

```


The values on the stack are just the runtime values we discussed [last time](https://bitrig.com/blog/swift-interpreter).

Then we can make a method to loop over the bytecode, switch over the different operation types, and process them. For the literals, we push the value they create onto our stack.

```

extension Interpreter {
    mutating func evaluateOperations() -> InterpreterResult {
        while let operation = nextOperation() {
            let result = evaluateOperation(operation)
            if result != .normal {
                return result
            }
        }
        return .normal
    }

    mutating func evaluateOperation(_ operation: Operation) -> InterpreterResult {
        switch operation {
        case .break:
            return .break
        case .continue:
            return .continue
        case .nilLiteral:
            valueStack.append(.nil)
            return .normal
        case .integerLiteral:
            valueStack.append(.native(nextInt()))
            return .normal
        case .doubleLiteral:
            valueStack.append(.native(nextDouble()))
            return .normal
        ...
    }
}

```


The result we return is just metadata about whether execution ended in any unusual way, which we need for loops, function calls, etc.

The final piece we need for the interpreter is a way to extract the necessary values from the bytecode array. This is effectively the inverse operation of what we did earlier to encode those values:

```

extension Interpreter {
    mutating func nextOperation() -> Operation? {
        let result = pc < bytecode.count ? bytecode[pc] : nil
        pc += 1
        return result.flatMap { .init(rawValue: $0.rawValue) }
    }

    mutating func nextInt() -> Int {
        Int(Int64(bitPattern: nextUInt64()))
    }

    mutating func nextDouble() -> Double {
        guard let value = nextUInt64() else { return 0.0 }
        return Double(bitPattern: value)
    }

    mutating func nextUInt64() -> UInt64 {
        if pc >= bytecode.count - 7 {
            print("ERROR: Attempt to read past bytecode")
            return nil
        }
        let result = UInt64(bytecode[pc].rawValue) << 56 |
            UInt64(bytecode[pc + 1].rawValue) << 48 |
            UInt64(bytecode[pc + 2].rawValue) << 40 |
            UInt64(bytecode[pc + 3].rawValue) << 32 |
            UInt64(bytecode[pc + 4].rawValue) << 24 |
            UInt64(bytecode[pc + 5].rawValue) << 16 |
            UInt64(bytecode[pc + 6].rawValue) << 8 |
            UInt64(bytecode[pc + 7].rawValue)
        pc += 8
        return result
    }
}

```


And now we have a working (but limited) bytecode interpreter!

* * *

What’s Next
-----------

So far we've covered how to get from source to basic, runnable bytecode. Next time, we'll look at encoding and evaluating more advanced expressions like function calls and initializers and how that ties into calling framework APIs that we saw [previously](https://bitrig.com/blog/swift-interpreter).

Follow our updates here and on [social media](https://linktr.ee/bitrig), and if you haven’t yet, give [Bitrig](https://apps.apple.com/us/app/bitrig/id6747835910) a try, it’s the easiest way to see this in action.

_Did you like learning about how Bitrig's interpreter works? Want to see it up close? [We're hiring: join us!](https://bitrig.com/jobs)_
