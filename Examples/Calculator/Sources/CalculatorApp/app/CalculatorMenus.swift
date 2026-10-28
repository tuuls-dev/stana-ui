import Stana

@MainActor enum CalculatorMenus {
	static func run(
		window: STNWindow,
		commands: (
			functions: STNCommand, evaluate: STNCommand, clear: STNCommand, copy: STNCommand, paste: STNCommand,
			graph: STNCommand, tape: STNCommand, degrees: STNCommand, save: STNCommand
		),
		windowCommands: (picture: STNCommand, diagnostics: STNCommand)
	) {
		let functions = commands.functions
		let evaluate = commands.evaluate
		let clear = commands.clear
		let copy = commands.copy
		let paste = commands.paste
		let graph = commands.graph
		let tape = commands.tape
		let degrees = commands.degrees
		let save = commands.save
		let picture = windowCommands.picture
		let diagnostics = windowCommands.diagnostics
		STNApplication.run(
			windows: [window],
			menus: [
				STNMenu(properties: .init(title: "File")) {
					save; picture
				},
				STNMenu(properties: .init(title: "Edit")) {
					paste; copy; clear
				},
				STNMenu(properties: .init(title: "View")) {
					graph; tape; degrees
				},
				STNMenu(properties: .init(title: "Calculate")) {
					evaluate; functions
				},
				STNMenu(properties: .init(title: "Help")) {
					functions; diagnostics
				},
			]
		)
	}
}
