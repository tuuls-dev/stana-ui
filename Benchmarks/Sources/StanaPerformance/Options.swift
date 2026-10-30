import Foundation

struct BenchmarkFailure: Error, CustomStringConvertible {
	let description: String

	init(_ description: String) {
		self.description = description
	}
}

struct Options {
	var workload = "all"
	var sizes = [100, 1_000]
	var samples = 30
	var warmup = 3
	var validate = false
	var list = false
	var output: String?

	init(_ arguments: [String]) throws {
		var index = 0
		if let first = arguments.first, !first.hasPrefix("--") {
			workload = first
			index += 1
		}

		while index < arguments.count {
			let flag = arguments[index]
			index += 1
			if flag == "--validate" {
				validate = true
				continue
			}

			if flag == "--list" {
				list = true
				continue
			}

			guard ["--sizes", "--samples", "--warmup", "--output"].contains(flag), index < arguments.count else {
				throw BenchmarkFailure("Unknown or incomplete option: \(flag)")
			}

			let value = arguments[index]
			index += 1
			switch flag {
			case "--sizes":
				let fields = value.split(separator: ",", omittingEmptySubsequences: false)
				let parsed = fields.compactMap { Int($0) }
				guard parsed.count == fields.count, !parsed.isEmpty,
					parsed.allSatisfy({ (1...100_000).contains($0) }), Set(parsed).count == parsed.count
				else {
					throw BenchmarkFailure("Sizes must be distinct integers in 1...100000")
				}

				sizes = parsed
			case "--samples":
				guard let count = Int(value), (1...10_000).contains(count) else {
					throw BenchmarkFailure("Samples must be in 1...10000")
				}

				samples = count
			case "--warmup":
				guard let count = Int(value), (0...10_000).contains(count) else {
					throw BenchmarkFailure("Warmup must be in 0...10000")
				}

				warmup = count
			default:
				guard !value.isEmpty else {
					throw BenchmarkFailure("Output path must not be empty")
				}

				output = value
			}
		}
	}
}
