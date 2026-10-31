import Foundation
import StanaCore

struct Options {
	var workload = "all"
	var sizes = [100, 1000]
	var samples = 30
	var warmup = 3
	var validate = false
	var counters = false
	var native = false
	var spans: Set<WorkSpan> = []
	var output: String?
	var list = false

	init(_ arguments: [String]) throws {
		var index = 0
		var named = false
		while index < arguments.count {
			let argument = arguments[index]
			func value() throws -> String {
				index += 1
				guard index < arguments.count else {
					throw Failure("Missing value for \(argument)")
				}
				return arguments[index]
			}

			switch argument {
			case "--list": list = true
			case "--validate": validate = true
			case "--counters": counters = true
			case "--sizes":
				let values = try value().split(separator: ",", omittingEmptySubsequences: false)
				let parsed = values.compactMap { Int($0) }
				guard parsed.count == values.count, parsed.allSatisfy({ $0 > 0 && $0 <= 100_000 }) else {
					throw Failure("Sizes must be comma-separated integers in 1...100000")
				}

				sizes = parsed
			case "--samples", "--warmup":
				guard let count = Int(try value()), count >= (argument == "--samples" ? 1 : 0) else {
					throw Failure("Invalid count for \(argument)")
				}

				if argument == "--samples" {
					samples = count
				} else {
					warmup = count
				}
			case "--text":
				let text = try value()
				guard ["test", "native"].contains(text) else {
					throw Failure("--text must be test or native")
				}
				native = text == "native"
			case "--spans":
				let names = try value()
				if names == "all" {
					spans = Set(WorkSpan.allCases)
				} else {
					for name in names.split(separator: ",", omittingEmptySubsequences: false) {
						guard let span = WorkSpan(rawValue: String(name)) else {
							throw Failure("Unknown span: \(name)")
						}
						spans.insert(span)
					}
				}
			case "--output": output = try value()
			default:
				guard !argument.hasPrefix("-"), !named else {
					throw Failure("Unknown argument: \(argument)")
				}
				workload = argument
				named = true
			}

			index += 1
		}

		guard workload == "all" || Workload(rawValue: workload) != nil else {
			throw Failure("Unknown workload")
		}
		guard !(validate && native) else {
			throw Failure("Native timing is separate from deterministic validation")
		}
	}
}

struct Failure: Error, CustomStringConvertible {
	let description: String

	init(_ description: String) {
		self.description = description
	}
}
