import Stana

@MainActor func invalidTextFieldAlignment() {
	_ = STNTextField.Options(alignment: .firstBaseline)
}
