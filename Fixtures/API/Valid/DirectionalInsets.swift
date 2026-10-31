import Stana

func directionalInsetsFixture() {
	let bounds = STNRect(width: 200, height: 100)
	let padding = STNInsets(top: 5, leading: 10, bottom: 5, trailing: 30)
	let _ = bounds.inset(by: padding)
	let _ = bounds.inset(by: padding, direction: .rightToLeft)
}
