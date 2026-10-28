import Foundation
import StanaPrimitives
import StanaScene

/// Immutable ABI payloads; native objects and worker ownership never cross into Swift.
@MainActor package final class MetalSceneEncoder {
	private struct Record {
		let children: [String]
		var references: Int = 0
	}
	private var records: [String: Record] = [:]
	private var objects: [String: [String: Any]] = [:]
	private var previousRoot: String?
	private var epoch: UInt64?

	package init() {}

	package func encode(_ scene: SceneSnapshot) throws -> Data {
		if epoch != scene.surfaceEpoch { records.removeAll(); previousRoot = nil; epoch = scene.surfaceEpoch }
		objects.removeAll(keepingCapacity: true)
		var value: [String: Any] = [
			"targetTimestamp": scene.targetTimestamp, "framePeriod": scene.framePeriod,
			"revision": String(scene.sceneRevision), "epoch": String(scene.surfaceEpoch),
			"base": String(scene.damageBaseRevision), "size": [scene.size.width, scene.size.height],
			"damage": scene.damage.map(Self.rect), "mode": scene.colorMode.rawValue,
			"extended": scene.paint?.requiresExtended ?? false,
		]
		if let paint = scene.paint {
			let root = group(paint)
			records[root]!.references += 1
			value["rootRef"] = root
			value["objects"] = objects
			if let previousRoot { release(previousRoot) }
			previousRoot = root
		} else {
			value["root"] = [
				"kind": "group", "id": "reference", "bounds": [0, 0, scene.size.width, scene.size.height],
				"transform": [1, 0, 0, 1, 0, 0], "opacity": 1, "clip": false, "radius": 0,
				"children": [
					[
						"kind": "cpu", "id": "reference", "version": String(scene.sceneRevision),
						"bounds": [0, 0, scene.size.width, scene.size.height],
						"commands": scene.commands.map(Self.command),
					]
				],
			]
		}
		do {
			return try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
		} catch {
			records.removeAll()
			previousRoot = nil
			throw error
		}
	}

	private func insert(_ id: String, object: [String: Any], children: [String]) {
		records[id] = Record(children: children)
		objects[id] = object
		for child in children { records[child]!.references += 1 }
	}

	private func release(_ id: String) {
		guard var record = records[id] else { return }
		record.references -= 1
		if record.references > 0 { records[id] = record; return }
		records.removeValue(forKey: id)
		for child in record.children { release(child) }
	}

	private func sequence(_ branch: PaintSequence.Branch?) -> String? {
		guard let branch else { return nil }
		let id = "sequence:" + branch.version.uuidString
		if records[id] != nil { return id }
		let left = sequence(branch.left), right = sequence(branch.right), entry = item(branch.entry)
		var object: [String: Any] = ["kind": "sequence", "entry": entry]
		object["left"] = left
		object["right"] = right
		insert(id, object: object, children: [left, entry, right].compactMap { $0 })
		return id
	}

	private func item(_ entry: PaintEntry) -> String {
		switch entry {
		case .group(let g): return group(g)
		case .cpu(let c):
			let id = "cpu:" + c.id.description + ":" + c.version.uuidString
			if records[id] == nil {
				insert(
					id,
					object: [
						"kind": "cpu", "id": c.id.description, "version": c.version.uuidString,
						"bounds": Self.rect(c.bounds), "commands": c.commands.map(Self.command),
					],
					children: []
				)
			}
			return id
		case .gpu(let g):
			let id = "gpu:" + g.id.description + ":" + g.version.uuidString
			if records[id] == nil {
				insert(
					id,
					object: [
						"kind": "gpu", "id": g.id.description, "version": g.version.uuidString,
						"bounds": Self.rect(g.bounds),
						"commands": g.drawing.commands.map { Self.gpuCommand($0, colors: g.colors) },
					],
					children: []
				)
			}
			return id
		}
	}

	private static func rect(_ r: STNRect) -> [Double] {
		[r.minX, r.minY, r.size.width, r.size.height]
	}

	private static func command(_ command: DrawCommand) -> [String: Any] {
		func color(_ c: STNColor) -> [Double] { [c.red, c.green, c.blue, c.alpha] }
		switch command {
		case .fill(let r, let c, let radius):
			return ["op": "fill", "rect": rect(r), "color": color(c), "radius": radius]
		case .stroke(let r, let c, let width, let radius):
			return ["op": "stroke", "rect": rect(r), "color": color(c), "width": width, "radius": radius]
		case .text(let text, let r, let font, let c, let wraps):
			return [
				"op": "text", "rect": rect(r), "color": color(c), "text": text, "size": font.size,
				"weight": font.weight.rawValue, "wraps": wraps,
			]
		case .image(let data, let r): return ["op": "image", "rect": rect(r), "data": data.base64EncodedString()]
		case .pushClip(let r): return ["op": "clip", "rect": rect(r)]
		case .popClip: return ["op": "unclip"]
		case .pushOpacity(let opacity): return ["op": "opacity", "opacity": opacity]
		case .popOpacity: return ["op": "endOpacity"]
		case .pushTransform(let t): return ["op": "transform", "matrix": [t.a, t.b, t.c, t.d, t.tx, t.ty]]
		case .popTransform: return ["op": "endTransform"]
		case .pushRoundedClip(let r, let radius): return ["op": "roundedClip", "rect": rect(r), "radius": radius]
		}
	}

	private func group(_ g: PaintGroup) -> String {
		let id = "group:" + g.id.description + ":" + g.version.uuidString
		if records[id] != nil { return id }
		let children = sequence(g.children.root)
		var result: [String: Any] = [
			"kind": "group", "id": g.id.description, "bounds": Self.rect(g.bounds),
			"version": g.version.uuidString,
			"transform": [g.transform.a, g.transform.b, g.transform.c, g.transform.d, g.transform.tx, g.transform.ty],
			"opacity": g.opacity, "clip": g.clips, "radius": g.radius,
		]
		result["sequence"] = children
		if let effect = g.backdrop {
			switch effect.operation {
			case .identity: result["backdrop"] = ["kind": "identity"]
			case .blur(let radius): result["backdrop"] = ["kind": "blur", "radius": radius]
			case .program(let p): result["backdrop"] = ["kind": "program", "program": Self.program(p)]
			}
		}
		insert(id, object: result, children: children.map { [$0] } ?? [])
		return id
	}

	private static func gpuCommand(_ command: GPUCommand, colors: GPUColorEnvironment) -> [String: Any] {
		func color(_ c: GPUColor) -> [String: Any] { ["color": c.resolved(in: colors), "linear": c.linear] }
		var result: [String: Any]
		switch command {
		case .rect(let r, let radius, let c):
			result = color(c)
			result.merge(["op": "rect", "rect": rect(r), "radius": radius]) { _, new in new }
		case .ellipse(let r, let c):
			result = color(c)
			result.merge(["op": "ellipse", "rect": rect(r)]) { _, new in new }
		case .polyline(let points, let width, let c, let closed):
			result = color(c)
			result.merge(["op": "polyline", "points": points.map { [$0.x, $0.y] }, "width": width, "closed": closed]) {
				_,
				new in new
			}
		case .mesh(let mesh):
			result = [
				"op": "mesh", "version": mesh.version.uuidString, "indices": mesh.indices,
				"vertices": mesh.vertices.map {
					[$0.position.x, $0.position.y, $0.color.red, $0.color.green, $0.color.blue, $0.color.alpha]
				},
			]
		case .program(let p): result = ["op": "program", "program": program(p)]
		}

		return result
	}

	private static func program(_ p: STNGPUProgram) -> [String: Any] {
		var result: [String: Any] = [
			"version": p.version.uuidString, "pipelineVersion": p.pipelineVersion.uuidString,
			"stateVersion": p.stateVersion.uuidString, "output": p.output,
			"color": p.outputColor.rawValue, "peak": p.sourcePeak,
			"passes": p.executionOrder.map { index -> [String: Any] in
				let pass = p.passes[index]
				let bindings = pass.bindings.map { b -> [String: Any] in
					[
						"resource": b.resource, "index": b.index, "access": b.access.rawValue,
						"stage": b.stage.rawValue, "previous": b.previous,
					]
				}
				switch pass {
				case .render(let r):
					var value: [String: Any] = [
						"kind": "render", "vertex": r.vertex, "fragment": r.fragment,
						"target": r.target, "count": r.vertexCount, "instances": r.instanceCount,
						"bindings": bindings, "blends": r.blends,
					]
					value["indices"] = r.indexBuffer
					return value
				case .compute(let c):
					return [
						"kind": "compute", "function": c.function, "threads": [c.width, c.height, c.depth],
						"bindings": bindings,
					]
				}
			},
		]
		switch p.shader {
		case .metalSource(let source): result["source"] = source
		case .metalLibrary(let data): result["library"] = data.base64EncodedString()
		}
		result["samplingRadius"] = p.samplingRadius

		result["resources"] = p.resources.mapValues { resource -> [String: Any] in
			switch resource {
			case .buffer(let b):
				return ["kind": "buffer", "version": b.version.uuidString, "data": b.data.base64EncodedString()]
			case .storage(let length): return ["kind": "storage", "length": length]
			case .texture(let t):
				return [
					"kind": "texture", "version": t.version.uuidString, "width": t.width,
					"height": t.height, "format": t.format.rawValue, "data": t.data.base64EncodedString(),
					"color": t.colorEncoding.rawValue, "premultiplied": t.premultiplied, "peak": t.sourcePeak,
				]
			case .target(let w, let h, let f): return ["kind": "target", "width": w, "height": h, "format": f.rawValue]
			case .state(let s):
				var value: [String: Any] = [
					"kind": "state", "width": s.width, "height": s.height,
					"format": s.format.rawValue, "reset": s.resetKey,
				]
				value["data"] = s.initialData?.base64EncodedString()
				return value
			case .sampler(let s): return ["kind": "sampler", "filter": s.filter.rawValue]
			}
		}
		result["constants"] = p.constants.mapValues { value -> [String: Any] in
			switch value {
			case .bool(let b): ["kind": "bool", "value": b]
			case .int(let i): ["kind": "int", "value": i]
			case .float(let f): ["kind": "float", "value": f]
			}
		}
		return result
	}
}
