import Stana

@main
struct EditableCollectionApp {
    @MainActor static func main() {
        let model = Model()
        let window = STNWindow(properties: .init(title: "Editable Collection", size: .init(width: 650, height: 500))) {
            STNVStack(properties: .init(spacing: 16, padding: 24)) {
                STNText(
                    properties: .init(
                        text: "Tasks", font: .system(size: 26, weight: .bold), accessibility: .init(heading: 1)))
                STNHStack(properties: .init(spacing: 12)) {
                    STNButton(properties: .init(text: "Add Task", onActivate: { model.add() }))
                    STNButton(properties: .init(text: "Reverse Order", onActivate: { model.reverse() }))
                }
                STNScrollView(properties: .init(frame: .init(width: 600, height: 340))) {
                    STNVStack(properties: .init(spacing: 8)) {
                        STNForEach(observableRows: model.rows, id: \.id) { todo in
                            TodoRow(properties: .init(todo: todo, onRemove: { model.remove(todo.id) }))
                        }
                    }
                }
            }
        }
        STNApplication.run(windows: [window])
    }
}
