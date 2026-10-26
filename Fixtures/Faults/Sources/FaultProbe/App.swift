import Foundation
import Stana

@main struct FaultProbe {
    @MainActor static func main() {
        switch CommandLine.arguments.last {
        case "cycle":
            var a: STNComputed<Int>!
            var b: STNComputed<Int>!
            a = STNComputed { b.value }
            b = STNComputed { a.value }
            _ = a.value
        case "write":
            let source = STNSignal(0)
            let computed = STNComputed {
                source.value += 1
                return source.value
            }
            _ = computed.value
        case "comparator":
            let other = STNSignal(0)
            let source = STNSignal(
                0,
                equals: { a, b in
                    other.value += 1
                    return a == b
                })
            source.value = 1
        default: fatalError("Unknown fault fixture")
        }
        fatalError("Runtime fault was not diagnosed")
    }
}
