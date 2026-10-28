import Compression
import Foundation

enum PNGImage {
	static func encode(width: Int, height: Int, rgba: [UInt8]) -> Data {
		precondition(rgba.count == width * height * 4)
		return encodeRows(width: width, height: height, rows: rgba)
	}

	static func encodeBGRA(width: Int, height: Int, bytes: Data) -> Data {
		precondition(bytes.count == width * height * 4)
		var rgba = [UInt8](repeating: 0, count: bytes.count)
		for pixel in 0..<(width * height) {
			let offset = pixel * 4
			rgba[offset] = bytes[offset + 2]
			rgba[offset + 1] = bytes[offset + 1]
			rgba[offset + 2] = bytes[offset]
			rgba[offset + 3] = bytes[offset + 3]
		}

		return encodeRows(width: width, height: height, rows: rgba)
	}

	private static func encodeRows(width: Int, height: Int, rows: [UInt8]) -> Data {
		var raw = [UInt8]()
		raw.reserveCapacity((width * 4 + 1) * height)
		for y in 0..<height {
			raw.append(0)
			let start = y * width * 4
			raw.append(contentsOf: rows[start..<(start + width * 4)])
		}

		var data = Data([137, 80, 78, 71, 13, 10, 26, 10])
		data.append(chunk(type: "IHDR", payload: header(width: width, height: height)))
		data.append(chunk(type: "IDAT", payload: zlib(raw)))
		data.append(chunk(type: "IEND", payload: Data()))
		return data
	}

	private static func header(width: Int, height: Int) -> Data {
		var payload = Data()
		payload.append(uint32(UInt32(width)))
		payload.append(uint32(UInt32(height)))
		payload.append(contentsOf: [8, 6, 0, 0, 0])
		return payload
	}

	private static func chunk(type: String, payload: Data) -> Data {
		var body = Data(type.utf8)
		body.append(payload)
		var data = uint32(UInt32(payload.count))
		data.append(body)
		data.append(uint32(crc32(body)))
		return data
	}

	private static func uint32(_ value: UInt32) -> Data {
		Data([
			UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF),
		])
	}

	private static func crc32(_ data: Data) -> UInt32 {
		var crc: UInt32 = 0xFFFF_FFFF
		for byte in data {
			crc ^= UInt32(byte)
			for _ in 0..<8 {
				let mask = (crc & 1) == 1 ? UInt32(0xEDB8_8320) : 0
				crc = (crc >> 1) ^ mask
			}
		}

		return crc ^ 0xFFFF_FFFF
	}

	private static func zlib(_ bytes: [UInt8]) -> Data {
		let capacity = bytes.count + bytes.count / 8 + 128
		let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
		defer {
			destination.deallocate()
		}

		let written = bytes.withUnsafeBytes { source in
			compression_encode_buffer(
				destination,
				capacity,
				source.bindMemory(to: UInt8.self).baseAddress!,
				bytes.count,
				nil,
				COMPRESSION_ZLIB
			)
		}
		precondition(written > 0, "PNG compression failed")
		// Apple's COMPRESSION_ZLIB emits raw DEFLATE; PNG requires the RFC 1950 wrapper.
		var stream = Data([0x78, 0x9C])
		stream.append(Data(bytes: destination, count: written))
		var a: UInt32 = 1
		var b: UInt32 = 0
		for byte in bytes {
			a = (a + UInt32(byte)) % 65521
			b = (b + a) % 65521
		}

		stream.append(uint32((b << 16) | a))
		return stream
	}
}
