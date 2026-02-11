import SwiftUI
import SwiftExecSemantic

struct LiveRenderedTreeView: View {
    @Bindable var store: RuntimeStore
    let dispatch: (String) -> Void

    var body: some View {
        ViewTreeRenderer.render(tree: store.ir, store: store, dispatch: dispatch)
    }
}

enum ViewTreeRenderer {
    static func render(
        tree: ViewTree,
        store: RuntimeStore,
        dispatch: @escaping (String) -> Void
    ) -> AnyView {
        render(node: tree.root, store: store, dispatch: dispatch)
    }

    static func render(
        node: ViewNode,
        store: RuntimeStore,
        dispatch: @escaping (String) -> Void
    ) -> AnyView {
        var content = baseView(node: node, store: store, dispatch: dispatch)
        content = applyModifiers(content, modifiers: node.modifiers)
        content = applyEvents(content, nodeType: node.type, events: node.events, store: store, dispatch: dispatch)
        return content
    }

    private static func baseView(
        node: ViewNode,
        store: RuntimeStore,
        dispatch: @escaping (String) -> Void
    ) -> AnyView {
        switch node.type {
        case "Text":
            let text = node.props["text"]?.stringValue ?? ""
            return AnyView(Text(text))

        case "Button":
            let title = node.props["title"]?.stringValue ?? "Button"
            let actionID = node.events.first(where: { $0.event == "tap" })?.actionID
            return AnyView(
                Button(title) {
                    guard let actionID else {
                        return
                    }
                    dispatch(actionID)
                }
            )

        case "VStack":
            let spacing = CGFloat(node.props["spacing"]?.doubleValue ?? 0)
            return AnyView(
                VStack(alignment: .leading, spacing: spacing) {
                    ForEach(node.children) { child in
                        render(node: child, store: store, dispatch: dispatch)
                    }
                }
            )

        case "HStack":
            let spacing = CGFloat(node.props["spacing"]?.doubleValue ?? 0)
            return AnyView(
                HStack(spacing: spacing) {
                    ForEach(node.children) { child in
                        render(node: child, store: store, dispatch: dispatch)
                    }
                }
            )

        case "Spacer":
            return AnyView(Spacer())

        case "TextField":
            let title = node.props["title"]?.stringValue ?? ""
            let path = node.props["text"]?.bindingPath
            let binding = path.map(store.bindingString) ?? .constant("")
            return AnyView(TextField(title, text: binding))

        case "Toggle":
            let title = node.props["title"]?.stringValue ?? ""
            let path = node.props["isOn"]?.bindingPath
            let binding = path.map(store.bindingBool) ?? .constant(false)
            return AnyView(Toggle(title, isOn: binding))

        case "Image":
            let name = node.props["name"]?.stringValue ?? "photo"
            return AnyView(Image(systemName: name))

        default:
            return AnyView(
                Text("Unsupported node: \(node.type)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            )
        }
    }

    private static func applyModifiers(_ view: AnyView, modifiers: [ViewNodeModifier]) -> AnyView {
        var current = view
        for modifier in modifiers {
            switch modifier.type {
            case "padding":
                if let value = modifier.params["value"]?.doubleValue {
                    current = AnyView(current.padding(CGFloat(value)))
                } else {
                    current = AnyView(current.padding())
                }

            case "font":
                if let style = modifier.params["value"]?.stringValue {
                    current = AnyView(current.font(font(named: style)))
                }

            case "foregroundStyle":
                if let style = modifier.params["value"]?.stringValue {
                    current = AnyView(current.foregroundStyle(color(named: style)))
                }

            case "frame":
                let width = modifier.params["width"]?.doubleValue.map(CGFloat.init)
                let height = modifier.params["height"]?.doubleValue.map(CGFloat.init)
                current = AnyView(current.frame(width: width, height: height))

            case "background":
                if let style = modifier.params["value"]?.stringValue {
                    current = AnyView(current.background(color(named: style)))
                }

            default:
                continue
            }
        }
        return current
    }

    private static func applyEvents(
        _ view: AnyView,
        nodeType: String,
        events: [ViewNodeEvent],
        store: RuntimeStore,
        dispatch: @escaping (String) -> Void
    ) -> AnyView {
        var current = view
        for event in events {
            switch event.event {
            case "tap":
                // Buttons already dispatch via their primary action.
                guard nodeType != "Button" else {
                    continue
                }
                current = AnyView(current.onTapGesture { dispatch(event.actionID) })

            case "onAppear":
                current = AnyView(current.onAppear { dispatch(event.actionID) })

            case "onChange":
                guard let path = event.path else {
                    continue
                }
                let token = store.observedToken(for: path)
                current = AnyView(
                    current.onChange(of: token) { _ in
                        dispatch(event.actionID)
                    }
                )

            default:
                continue
            }
        }
        return current
    }

    private static func color(named value: String) -> Color {
        switch value.lowercased() {
        case "red":
            return .red
        case "green":
            return .green
        case "blue":
            return .blue
        case "orange":
            return .orange
        case "yellow":
            return .yellow
        case "pink":
            return .pink
        case "purple":
            return .purple
        case "gray", "grey":
            return .gray
        case "black":
            return .black
        case "white":
            return .white
        case "secondary":
            return .secondary
        default:
            return .primary
        }
    }

    private static func font(named value: String) -> Font {
        switch value.lowercased() {
        case "largeTitle".lowercased():
            return .largeTitle
        case "title":
            return .title
        case "title2":
            return .title2
        case "title3":
            return .title3
        case "headline":
            return .headline
        case "subheadline":
            return .subheadline
        case "caption":
            return .caption
        case "caption2":
            return .caption2
        case "footnote":
            return .footnote
        default:
            return .body
        }
    }
}

private extension IRValue {
    var bindingPath: String? {
        if case let .bindingRef(path) = self {
            return path
        }
        return nil
    }
}
