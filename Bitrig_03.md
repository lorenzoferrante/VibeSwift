# Bitrig’s Swift Interpreter: From Expressions to APIs
[Bitrig](https://apps.apple.com/us/app/bitrig/id6747835910) dynamically generates and runs Swift apps right on your phone. Normally, running Swift code would require compiling and signing with Xcode, which you can’t do on an iPhone. One of the most common questions we’re asked is: _how does this work_?

Welcome to Part 3 in our series on how we built Bitrig's Swift interpreter. [In Part 1](https://bitrig.com/blog/swift-interpreter), we introduced the core idea: interpreting Swift from Swift itself and dynamically bridging into existing APIs. [In Part 2](https://bitrig.com/blog/interpreter-bytecode), we covered the mechanics of converting Swift code to bytecode. In this post, we'll explain how complex expressions are evaluated at runtime and how they connect to real system framework APIs.

* * *

Representing Methods
--------------------

Our interpreter uses a [stack machine](https://en.wikipedia.org/wiki/Stack_machine) to store intermediate values while evaluating expressions. We added the value stack to our interpreter last time, but we didn’t examine how it’s used.

Consider the expression `"Hello " + name.uppercased()`. It requires multiple evaluations that need to be combined. In pseudo-code:

```

valueStack.push(evaluate(name))
valueStack.push(evaluate(valueStack.pop().uppercased()))
valueStack.push(evaluate("Hello "))
valueStack.push(evaluate(valueStack.pop() + valueStack.pop()))

```


The stack provides a uniform place to store any number of intermediate values for any kind of expression.

Notice how the final push isn’t popped? That’s the function’s return value.

* * *

Next, let’s look at how we evaluate more complex expressions like `name.uppercased()`.

The first step is to add instructions for encoding this into the bytecode stream:

```

extension [Bytecode] {
    mutating func appendMethodCall(
        base: ExprSyntax, method: DeclReferenceExprSyntax, arguments: LabeledExprListSyntax
    ) {
        base.appendBytecode(&self)
        appendMethodName(method.baseName.text)
        var argumentCode: [Bytecode] = []
        for argument in arguments {
            argument.expression.appendBytecode(&argumentCode)
        }
        appendInt(arguments.count)
        append(contentsOf: argumentCode)
    }
}

```


From [Part 2](https://bitrig.com/blog/interpreter-bytecode), we already have functions for encoding expressions. Those functions can be used here to encode the base expression, the number of arguments, and each argument expression.

To implement `appendMethodName`, we assign a unique integer to every method name in the SDK and encode that into the bytestream. For example:

```

extension [Bytecode] {
    mutating func appendMethodName(_ name: String) {
        switch name {
        case "lowercased": appendInt(0)
        case "uppercased": appendInt(1)
        case "contains": appendInt(2)
        ...
        default: break
        }
    }
}

```


* * *

Evaluating Methods
------------------

To evaluate a method call, the interpreter first needs to decode its components from the bytestream:

```

extension Interpreter {
    func beginMethodCall() {
        guard let base = pop() else { return }
        let method = nextSymbol()
        let argumentCount = nextInt()
        var arguments: [Argument] = []
        arguments.reserveCapacity(argumentCount)
        for _ in 0..<argumentCount {
            if let arg = pop() {
                arguments.append(Argument(value: arg))
            }
        }

        evaluateMethodCall(base: base, method: method, arguments: arguments)
    }
}

```


Then it can call into the corresponding framework API:

```

func evaluateMethodCall(base: InterpreterValue, method: Int, arguments: [Argument]) -> Any? {
    switch method {
        case 0: // lowercased
            if let value = base.stringValue {
                return value.lowercased()
            } else if let value = base.characterValue {
                return value.lowercased()
            }
        case 1: // uppercased
            if let value = base.stringValue {
                return value.uppercased()
            } else if let value = base.characterValue {
                return value.uppercased()
            }
        case 2: // contains
            if let value = base.stringValue {
                return value.contains(arguments.first?.value.stringValue ?? "")
            }
        ...
        default: break
    }
    return nil
}

```


This is similar to the implementation of `evaluateInitializer` from [Part 1](https://bitrig.com/blog/swift-interpreter). The interpreter switches over the integers assigned to each method name and checks each type that has a method of the given name.

(One detail we’ve glossed over: arguments can have labels as well. Those can be handled by encoding the labels and pushing or popping them on a `labelStack` just like the `valueStack`.)

* * *

Sidenote: Operators
-------------------

Operators are represented and evaluated similarly to methods:

*   Each operator name is assigned a unique integer
*   The left-hand and right-hand sides are encoded and decoded the same way as the base and argument expressions in a method call
*   The call into the corresponding framework API is evaluated by switching over the operator and checking the type

The only added complexity is operator precedence. For example, with `x + y * z` the interpreter must evaluate `*` before `+`. Fortunately, SwiftSyntax includes a framework that solves this!

[SwiftOperators](https://swiftpackageindex.com/swiftlang/swift-syntax/602.0.0/documentation/SwiftOperators) can fold a flat sequence of operators into a structured tree that respects the correct precedence:

```

let rawFile = Parser.parse(source: code)
let processedFile = try operators.foldAll(parser)

```


Once folded, operators can be handled the same way as methods.

* * *

Extracting APIs
---------------

We extract the APIs the interpreter calls from the SDK’s `.swiftinterface` files. These files are valid Swift code, which means we can parse them directly with SwiftSyntax. Normally, we use SwiftSyntax to convert dynamically generated code into bytecode, but here we use it to preprocess the SDK itself.

A script processes each framework’s `.swiftinterface`, iterates through its declarations, and generates code:

*   For each type, its initializers go into `evaluateInitializer`.
*   For each method, a case is added to `evaluateMethodCall` and to the lookup table used by `appendMethodName`.

This approach also works for Objective-C frameworks because Xcode can emit a Swift version of an Objective-C framework’s interface. Since many iOS frameworks are still Objective-C under the hood, this greatly expands what the interpreter can access.

* * *

Over the course of this series, we’ve gone from the big picture down to the nuts and bolts: starting with the idea of interpreting Swift in Swift, exploring how source code is translated into bytecode, and finally showing how expressions and APIs are resolved so real Swift code can run. Each piece—parsing, bytecode execution, and API extraction—fits together into a system that makes it possible to run Swift apps instantly, without compiling.

What I find most exciting about the interpreter are the possibilities that come from treating Swift not just as a compiled language, but as a dynamic, interpretable one. I hope this peek behind the curtain inspires you to imagine new ways of building with Swift.

* * *

Follow our updates here and on [social media](https://linktr.ee/bitrig), and if you haven’t yet, give [Bitrig](https://apps.apple.com/us/app/bitrig/id6747835910) a try, it’s the easiest way to see this in action.

_Did you like learning about how Bitrig's interpreter works? Want to see it up close? [We're hiring: join us!](https://bitrig.com/jobs)_
