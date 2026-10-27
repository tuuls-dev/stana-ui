import StanaPrimitives

@resultBuilder @MainActor public enum STNBuilder {
	public static func buildExpression<C: STNComponent>(_ component: C) -> STNGroup {
		.init(components: [component])
	}

	public static func buildExpression(_ registration: Void) -> STNGroup {
		STNGroup()
	}

	public static func buildBlock(_ groups: STNGroup...) -> STNGroup {
		.init(components: groups.flatMap(\.components))
	}

	public static func buildOptional(_ group: STNGroup?) -> STNGroup {
		group ?? .init(components: [])
	}

	public static func buildEither(first: STNGroup) -> STNGroup {
		first
	}

	public static func buildEither(second: STNGroup) -> STNGroup {
		second
	}

	public static func buildArray(_ groups: [STNGroup]) -> STNGroup {
		.init(components: groups.flatMap(\.components))
	}

	public static func buildLimitedAvailability(_ group: STNGroup) -> STNGroup {
		group
	}
}
