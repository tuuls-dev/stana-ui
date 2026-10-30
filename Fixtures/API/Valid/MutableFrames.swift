import Stana

@MainActor func mutableFrameFixtures() {
	var frame = STNFrame()
	frame.maxWidth = .infinity
	frame.maxHeight = .infinity
	let signal = STNSignal(frame)
	let _ = STNBox(properties: .init(layout: .init(frame: signal))) {}
	signal.value.maxWidth = 200
	signal.value.maxHeight = 100
	signal.value.maxWidth = .infinity
	signal.value.maxHeight = .infinity
}
