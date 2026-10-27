import CStanaMacOS

extension String {
    /// The borrowed bytes remain valid for the entire synchronous native call.
    package func withNativeUTF8<Result>(_ body: (stn_utf8) throws -> Result) rethrows -> Result {
        try utf8CString.withUnsafeBufferPointer { try body(stn_utf8(bytes: $0.baseAddress, length: $0.count - 1)) }
    }
}

extension stn_utf8 {
    package var string: String {
        guard let bytes else { return "" }
        return String(
            decoding: UnsafeBufferPointer(
                start: UnsafeRawPointer(bytes).assumingMemoryBound(to: UInt8.self), count: length), as: UTF8.self)
    }
}
