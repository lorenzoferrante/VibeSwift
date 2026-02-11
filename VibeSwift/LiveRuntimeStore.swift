import Foundation
import Observation
import SwiftUI
import SwiftExecSemantic

@MainActor
@Observable
final class RuntimeStore {
    enum PathComponent: Hashable {
        case key(String)
        case index(Int)
    }

    var state: [String: IRValue]
    var ir: ViewTree
    var onStateMutation: ((String) -> Void)?

    init(
        state: [String: IRValue] = [:],
        ir: ViewTree = .empty
    ) {
        self.state = state
        self.ir = ir
    }

    func value(at path: String) -> IRValue? {
        let components = parse(path: path)
        guard let first = components.first else {
            return nil
        }
        guard case let .key(rootKey) = first else {
            return nil
        }
        guard var current = state[rootKey] else {
            return nil
        }
        for component in components.dropFirst() {
            switch component {
            case let .key(key):
                guard case let .object(object) = current, let nested = object[key] else {
                    return nil
                }
                current = nested
            case let .index(index):
                guard case let .array(array) = current, array.indices.contains(index) else {
                    return nil
                }
                current = array[index]
            }
        }
        return current
    }

    func setValue(_ value: IRValue, at path: String, triggerRecompute: Bool = true) {
        let components = parse(path: path)
        guard let first = components.first else {
            return
        }
        guard case let .key(rootKey) = first else {
            return
        }
        let next = setNestedValue(
            current: state[rootKey],
            remaining: Array(components.dropFirst()),
            to: value
        )
        state[rootKey] = next
        if triggerRecompute {
            onStateMutation?(path)
        }
    }

    func bindingBool(_ path: String) -> Binding<Bool> {
        Binding(
            get: { [weak self] in
                self?.value(at: path)?.boolValue ?? false
            },
            set: { [weak self] next in
                self?.setValue(.bool(next), at: path)
            }
        )
    }

    func bindingString(_ path: String) -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.value(at: path)?.stringValue ?? ""
            },
            set: { [weak self] next in
                self?.setValue(.string(next), at: path)
            }
        )
    }

    func bindingDouble(_ path: String) -> Binding<Double> {
        Binding(
            get: { [weak self] in
                self?.value(at: path)?.doubleValue ?? 0
            },
            set: { [weak self] next in
                self?.setValue(.double(next), at: path)
            }
        )
    }

    func observedToken(for path: String) -> String {
        guard let value = value(at: path) else {
            return "nil"
        }
        return render(value)
    }

    private func setNestedValue(
        current: IRValue?,
        remaining: [PathComponent],
        to value: IRValue
    ) -> IRValue {
        guard let head = remaining.first else {
            return value
        }
        let tail = Array(remaining.dropFirst())

        switch head {
        case let .key(key):
            var object: [String: IRValue]
            if case let .object(existing)? = current {
                object = existing
            } else {
                object = [:]
            }
            let nested = setNestedValue(current: object[key], remaining: tail, to: value)
            object[key] = nested
            return .object(object)

        case let .index(index):
            var array: [IRValue]
            if case let .array(existing)? = current {
                array = existing
            } else {
                array = []
            }
            if array.count <= index {
                array.append(contentsOf: Array(repeating: IRValue.null, count: index - array.count + 1))
            }
            array[index] = setNestedValue(current: array[index], remaining: tail, to: value)
            return .array(array)
        }
    }

    private func parse(path: String) -> [PathComponent] {
        var result: [PathComponent] = []
        var token = ""
        var index = path.startIndex

        func flushToken() {
            guard !token.isEmpty else {
                return
            }
            result.append(.key(token))
            token = ""
        }

        while index < path.endIndex {
            let char = path[index]
            if char == "." {
                flushToken()
                index = path.index(after: index)
                continue
            }
            if char == "[" {
                flushToken()
                let start = path.index(after: index)
                guard let close = path[start...].firstIndex(of: "]") else {
                    token.append(char)
                    index = path.index(after: index)
                    continue
                }
                let rawIndex = path[start..<close]
                if let value = Int(rawIndex) {
                    result.append(.index(value))
                } else if !rawIndex.isEmpty {
                    result.append(.key(String(rawIndex)))
                }
                index = path.index(after: close)
                continue
            }
            token.append(char)
            index = path.index(after: index)
        }
        flushToken()

        if result.isEmpty, !path.isEmpty {
            return [.key(path)]
        }
        return result
    }

    private func render(_ value: IRValue) -> String {
        switch value {
        case .null:
            return "null"
        case let .bool(v):
            return String(v)
        case let .int(v):
            return String(v)
        case let .double(v):
            return String(v)
        case let .string(v):
            return v
        case let .array(values):
            return "[" + values.map(render).joined(separator: ",") + "]"
        case let .object(values):
            let rendered = values
                .keys
                .sorted()
                .map { key in "\(key):\(render(values[key] ?? .null))" }
                .joined(separator: ",")
            return "{\(rendered)}"
        case let .stateRef(path), let .bindingRef(path):
            return path
        }
    }
}

private extension ViewTree {
    static var empty: ViewTree {
        ViewTree(
            irVersion: 1,
            capabilities: [],
            root: ViewNode(
                id: "root-empty",
                type: "VStack",
                props: [:],
                children: [],
                modifiers: [],
                events: []
            )
        )
    }
}
