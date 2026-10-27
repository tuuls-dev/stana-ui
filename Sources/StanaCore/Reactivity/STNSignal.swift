/// Current state on the UI executor. Reading `value` during construction captures
/// a constant; pass the signal itself to a reactive component property instead.
@MainActor public final class STNSignal<Value> {
	package let node: ValueNode<Value>

	public init(_ value: Value, equals: @escaping (Value, Value) -> Bool) {
		node = ValueNode(value: value, equals: equals)
	}

	public convenience init(_ value: Value) where Value: Equatable {
		self.init(value, equals: { $0 == $1 })
	}

	public var value: Value {
		get {
			node.read()
		}
		set {
			node.write(newValue)
		}
	}

	public var binding: STNBinding<Value> {
		.init(get: { self.value }, set: { self.value = $0 })
	}

	public func map<Output>(_ transform: @escaping (Value) -> Output, equals: @escaping (Output, Output) -> Bool)
		-> STNComputed<Output>
	{
		STNComputed({ transform(self.value) }, equals: equals)
	}

	public func map<Output: Equatable>(_ transform: @escaping (Value) -> Output) -> STNComputed<Output> {
		map(transform, equals: { $0 == $1 })
	}

	public func subscribe(_ receive: @escaping @MainActor (Value) -> Void) -> STNSubscription {
		weak var delivery: ValueObservation<Value>?
		let observation = ValueObservation(read: { self.value }, equals: node.equals) { value in
			ReactiveRuntime.shared.afterCommit {
				if delivery?.active == true {
					receive(value)
				}
			}
		}
		delivery = observation
		let token = STNSubscription(observation)
		ReactiveRuntime.shared.batch { ReactiveRuntime.shared.enqueue(observation) }
		return token
	}
}

@MainActor public final class STNComputed<Value> {
	package let node: ValueNode<Value>

	public init(_ compute: @escaping () -> Value, equals: @escaping (Value, Value) -> Bool) {
		node = ValueNode(compute: compute, equals: equals)
	}

	public convenience init(_ compute: @escaping () -> Value) where Value: Equatable {
		self.init(compute, equals: { $0 == $1 })
	}

	public var value: Value {
		node.read()
	}

	public func map<Output>(_ transform: @escaping (Value) -> Output, equals: @escaping (Output, Output) -> Bool)
		-> STNComputed<Output>
	{
		.init({ transform(self.value) }, equals: equals)
	}

	public func map<Output: Equatable>(_ transform: @escaping (Value) -> Output) -> STNComputed<Output> {
		map(transform, equals: { $0 == $1 })
	}
}

@MainActor public struct STNBinding<Value> {
	private let get: () -> Value
	private let set: (Value) -> Void

	public init(get: @escaping @MainActor () -> Value, set: @escaping @MainActor (Value) -> Void) {
		self.get = get
		self.set = set
	}

	public var value: Value {
		get {
			get()
		}
		nonmutating set {
			set(newValue)
		}
	}
}

@MainActor public final class STNSubscription {
	private let observation: Observation

	package init(_ observation: Observation) {
		self.observation = observation
	}

	public func cancel() {
		observation.cancel()
	}

	public var isCancelled: Bool {
		!observation.active
	}
}

public enum STNTransaction {
	/// Synchronously batches writes. Nested batches join; source writes are not rolled back.
	@MainActor public static func perform(_ updates: () -> Void) {
		ReactiveRuntime.shared.batch(updates)
	}
}
