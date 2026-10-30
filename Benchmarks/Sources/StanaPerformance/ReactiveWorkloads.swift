import Stana

@MainActor enum ReactiveWorkloads {
	static let all: [Workload] = [
		Workload(
			name: "signal-fanout",
			boundary: "One changed signal write through synchronous delivery to N existing subscribers",
			makeTrial: { size in
				let signal = STNSignal(0)
				var deliveries = 0
				var sum = 0
				let subscriptions = (0..<size)
					.map { _ in
						signal.subscribe {
							deliveries += 1
							sum += $0
						}
					}
				deliveries = 0
				return Trial(
					operation: { signal.value = 1 },
					verify: {
						try require(deliveries == size && sum == size, "Fanout delivery mismatch")
						return ["deliveries": deliveries]
					},
					cleanup: { subscriptions.forEach { $0.cancel() } }
				)
			}
		),
		Workload(
			name: "signal-equal-write",
			boundary: "One equal signal write with N existing subscribers; equality-suppression control",
			makeTrial: { size in
				let signal = STNSignal(0)
				var deliveries = 0
				let subscriptions = (0..<size).map { _ in signal.subscribe { _ in deliveries += 1 } }
				deliveries = 0
				return Trial(
					operation: { signal.value = 0 },
					verify: {
						try require(deliveries == 0, "Equal write delivered a value")
						return ["deliveries": deliveries]
					},
					cleanup: { subscriptions.forEach { $0.cancel() } }
				)
			}
		),
		Workload(
			name: "computed-diamond",
			boundary: "One source write and demand of a sum through N previously evaluated computed branches",
			makeTrial: { size in
				let signal = STNSignal(0)
				var evaluations = 0
				let branches = (0..<size)
					.map { index in
						STNComputed {
							evaluations += 1
							return signal.value + index
						}
					}
				let total = STNComputed { branches.reduce(0) { $0 + $1.value } }
				let initial = total.value
				evaluations = 0
				var observed = 0
				return Trial(
					operation: {
						signal.value = 1
						observed = total.value
					},
					verify: {
						try require(observed == initial + size && evaluations == size, "Computed demand mismatch")
						return ["evaluations": evaluations, "observedSum": observed]
					},
					cleanup: {}
				)
			}
		),
	]
}
