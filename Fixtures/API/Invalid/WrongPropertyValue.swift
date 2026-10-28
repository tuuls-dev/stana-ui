import Stana

@MainActor func invalid() {
	_ = STNLayoutProperties(frame: STNSignal("not a frame"))
}
