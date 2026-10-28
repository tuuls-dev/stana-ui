import Stana

@MainActor func invalid() {
	_ = STNCanvas(properties: .init(drawing: STNDrawing(), textStyle: .init(font: STNFont.system())))
}
