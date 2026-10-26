import Foundation
import StanaPrimitives

public enum STNCaretAffinity: Sendable { case upstream, downstream }

public struct STNTextPosition: Equatable, Sendable {
    public let utf8Offset: Int
    public let revision: UInt64
    public let affinity: STNCaretAffinity
    public init(utf8Offset: Int, revision: UInt64, affinity: STNCaretAffinity = .downstream) {
        self.utf8Offset = utf8Offset
        self.revision = revision
        self.affinity = affinity
    }
}

public struct STNTextSelection: Equatable, Sendable {
    public let anchor: STNTextPosition
    public let head: STNTextPosition
    public init(anchor: STNTextPosition, head: STNTextPosition) {
        self.anchor = anchor
        self.head = head
    }
}

package enum TextIndices {
    package static func index(utf8 offset: Int, in text: String) throws -> String.Index {
        guard offset >= 0, offset <= text.utf8.count,
            let index = String.Index(text.utf8.index(text.utf8.startIndex, offsetBy: offset), within: text)
        else { throw STNError.invalidTextRange }
        return index
    }
    package static func range(utf16 range: NSRange, in text: String) throws -> Range<String.Index> {
        guard range.location != NSNotFound, range.location >= 0, range.length >= 0,
            range.location <= text.utf16.count, range.length <= text.utf16.count - range.location,
            let result = Range(range, in: text)
        else { throw STNError.invalidTextRange }
        let units = Array(text.utf16)
        for endpoint in [range.location, range.location + range.length] where endpoint > 0 && endpoint < units.count {
            if (0xDC00...0xDFFF).contains(units[endpoint]) && (0xD800...0xDBFF).contains(units[endpoint - 1]) {
                throw STNError.invalidTextRange
            }
        }
        return result
    }
    package static func utf8(utf16 offset: Int, in text: String) throws -> Int {
        let range = try range(utf16: NSRange(location: offset, length: 0), in: text)
        return text.utf8.distance(from: text.utf8.startIndex, to: range.lowerBound)
    }
    package static func utf16(utf8 offset: Int, in text: String) throws -> Int {
        let index = try index(utf8: offset, in: text)
        return text.utf16.distance(from: text.utf16.startIndex, to: index)
    }
}
