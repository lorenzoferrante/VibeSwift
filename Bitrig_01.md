# Bitrig’s Swift Interpreter: Building an interpreter for Swift in Swift
Bitrig dynamically generates and runs Swift apps on your phone. Normally this would require compiling and signing with Xcode, and you can’t do that on an iPhone.

To make it possible to instantly run your app, we built a Swift interpreter. But it’s an unusual interpreter, since it interprets from Swift… to Swift. One of the top questions we’ve gotten is how it’s implemented, so we wanted to share how it works. To make this more accessible and interesting, we simplified some of the more esoteric details. But we hope you’ll come away with a high-level picture of how the interpreter works.

The Swift project helpfully provides a way to reuse all of the parsing logic from the compiler: [SwiftSyntax](https://github.com/swiftlang/swift-syntax). This made our job a lot easier. We can easily take some Swift code and get a parsed tree out of it, which we can use to evaluate and call into to get dynamic runtime values. Let’s dig deeper.

We can start with generating the simplest kind of runtime values. For any literals (strings, floating point numbers, integers, and booleans), we can create corresponding Swift instances (`String`, `Double`, `Int`, `Bool`) to represent them. Since we’re not compiling this, we don’t know ahead of time what all the types will be, so we need to type erase all instances. Let’s make an enum to represent these runtime interpreter values (since we'll have multiple kinds soon):

```

enum InterpreterValue {
    case nativeValue(Any)
}

```


Next, we'll expand our interpreter runtime values to be able to represent developer-defined types, too. Let’s say we have a struct with two fields: a string and an integer. We’ll store it as a type that has a dictionary mapping from the property name to the runtime value. When an initializer gets called, we simply need to map the arguments to the property names and populate the dictionary.

```

enum InterpreterValue {
    case nativeValue(Any)
    case customInstance(CustomInstance)
}
struct CustomInstance {
    var type: InterpreterType
    var values: [String: InterpreterValue]
}

```


But, what happens when we want to call an API that comes from a framework, like SwiftUI? For example, let’s say we have a call to `Text("Hello World")`. We don’t want to rewrite all of the APIs, the whole benefit of making a native app is being able to call into those implementations! Well, those APIs are available for us to call into since the interpreter is also written in Swift (naturally!). We just need to change from a dynamic call to a compiled one. We can do that by pre-compiling a call to the `Text` initializer that can take dynamic arguments. Something like this:

```

func evaluateTextInitializer(arguments: [Argument]) -> Text {
  Text(arguments.first?.value.stringValue ?? "")
}

```


But of course, we need more than just the `Text` initializer, so we'll generalize this to any initializer we might be called with:

```

func evaluateInitializer(type: String, arguments: [Argument]) -> Any? {
  if type == "Text" {
    return Text(arguments.first?.value.stringValue ?? "")
  } else if type == "Image" {
    return Image(arguments.first?.value.stringValue ?? "")
  ...
}

```


We can follow this same pattern for all other API types: function calls, properties, subscripts, etc. The difficult part is that there are a **lot** of APIs. It’s not practical to hand-write code to call into all of them, but fortunately there is a structured list of all of them: the .swiftinterface file for each framework. We can parse those files to get a list of all of the APIs we need and then generate the necessary code to call into them.

One interesting thing about taking this approach to its most extreme is that even very basic operations that you might expect any interpreter to implement, like basic numeric operations, can still call into their framework implementations. So this kind of interpreter doesn’t know how to calculate or evaluate anything itself, and is really more of a glorified [foreign function interface](https://en.wikipedia.org/wiki/Foreign_function_interface), but from dynamic Swift to compiled Swift.

One last important challenge is how to make custom types conform to framework protocols. For example, how do we make a custom SwiftUI `View`? Well, at runtime, we need a concrete type that conforms to the desired protocol. To do this, we can make stub types that conform to the protocol, but instead of having any logic of their own, simply call out to the interpreter to implement any requirements. Let’s look at `Shape`, a simple example:

```

struct ShapeStub: Shape {
    var interpreter: Interpreter
    var instance: CustomInstance

    var layoutDirectionBehavior: LayoutDirectionBehavior {
        instance.instanceMemberProperty("layoutDirectionBehavior", interpreter: interpreter).layoutDirectionBehaviorValue
    }
    func path(in rect: CGRect) -> Path {
        let arguments = [Argument(label: "in", value: rect)]
        return instance.instanceFunction("path", arguments: arguments, interpreter: interpreter).pathValue
    }
}

```


Coming back to `View`, this works the same way, with a little extra complexity because of the associated type that we have to type erase:

```

struct ViewStub: View {
    var interpreter: Interpreter
    var instance: CustomInstance

    var body: AnyView {
        instance.instanceMemberProperty("body", interpreter: interpreter).viewValue
            .map { AnyView($0) }
    }
}

```


And now we can make views that have dynamic implementations!

* * *

That’s a broad survey of how the interpreter is implemented. If you want to try it out in practice, download [Bitrig](https://apps.apple.com/us/app/bitrig/id6747835910)!

If there’s more you want to know about the interpreter, or Bitrig as a whole, let us know!

_Did you like learning about how Bitrig's interpreter works? Want to see it up close? [We're hiring: join us!](https://bitrig.com/jobs)_
