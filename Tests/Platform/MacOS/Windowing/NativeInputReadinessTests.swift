import AppKit
import Foundation
import Stana
import StanaCore
import StanaPrimitives
import StanaScene
import Testing

@testable import StanaPlatformMacOS

extension NativeWindowServer {
	@Suite(.serialized)
	@MainActor struct NativeInputReadinessTests {
		private func wait(_ condition: () -> Bool) async throws {
			for _ in 0..<600 {
				if condition() {
					return
				}

				try await Task.sleep(for: .milliseconds(10))
			}

			try #require(condition(), "Native presentation/input readiness did not recover")
		}

		@Test func firstCoordinateClickWorksInSheetsSecondaryAndChildWindowsAfterHiddenPreparationAndReopen()
			async throws
		{
			try await runForegroundInputProbe()
		}

		@Test func resizeCancelsStalePreparationAndStartsTheNewestDesiredScene() async throws {
			let window = try MacOSWindow(title: "Resize pending raster", size: .init(width: 200, height: 160))
			defer { window.close() }
			var failures: [String] = []
			window.graphics.onFailure = { failures.append($0) }
			window.graphics.configureForTesting(mode: 1, rasterDelay: 0.1, starved: true)

			func scene(_ revision: UInt64, size: STNSize) -> SceneSnapshot {
				SceneSnapshot(
					documentRevision: revision,
					sceneRevision: revision,
					surfaceEpoch: window.graphics.surfaceEpoch,
					damageBaseRevision: 0,
					damage: [.init(width: size.width, height: size.height)],
					commands: [.fill(.init(width: size.width, height: size.height), .white, radius: 0)],
					size: size
				)
			}

			_ = try window.graphics.submit(scene(1, size: .init(width: 200, height: 160)))
			try await Task.sleep(for: .milliseconds(20))
			let previousEpoch = window.graphics.surfaceEpoch
			window.nativeWindow.setContentSize(.init(width: 240, height: 180))
			#expect(window.graphics.surfaceEpoch > previousEpoch)
			_ = try window.graphics.submit(scene(2, size: .init(width: 240, height: 180)))
			try await wait { window.graphics.backingRevision == 2 }
			#expect(window.graphics.presentation.confirmed == nil)
			#expect(failures.isEmpty)
		}

		@Test func closingDuringRasterPreparationCannotResurrectTheHostOrRetainLeases() async throws {
			let device = try #require(MetalDevice.shared)
			let before = device.accounting.bytes
			var weakWindow: MacOSWindow?
			weak var released: MacOSWindow?
			do {
				let window = try MacOSWindow(title: "Close pending raster", size: .init(width: 200, height: 160))
				weakWindow = window
				released = window
				window.graphics.configureForTesting(mode: 1, rasterDelay: 0.1, starved: true)
				let scene = SceneSnapshot(
					documentRevision: 1,
					sceneRevision: 1,
					surfaceEpoch: window.graphics.surfaceEpoch,
					damageBaseRevision: 0,
					damage: [.init(width: 200, height: 160)],
					commands: [.fill(.init(width: 200, height: 160), .white, radius: 0)],
					size: .init(width: 200, height: 160)
				)
				_ = try window.graphics.submit(scene)
				try await Task.sleep(for: .milliseconds(20))
				window.close()
			}

			weakWindow = nil
			try await wait { released == nil && device.accounting.bytes <= before }
			#expect(weakWindow == nil)
		}
	}
}

/// The background SwiftPM helper can remain occluded; use a foreground app.
@MainActor private func runForegroundInputProbe() async throws {
	var root = URL(fileURLWithPath: #filePath)
	for _ in 0..<5 {
		root.deleteLastPathComponent()
	}

	let files = FileManager.default
	let override = ProcessInfo.processInfo.environment["STANA_NATIVE_INPUT_PROBE"]
	let candidates =
		override.map { [URL(fileURLWithPath: $0)] } ?? [
			root.appendingPathComponent(".build/out/Products/Debug/NativeInputProbe"),
			root.appendingPathComponent(".build/debug/NativeInputProbe"),
		]
	let executable = try #require(
		candidates.first { files.isExecutableFile(atPath: $0.path) },
		"Build NativeInputProbe first (just test-gui does this automatically)"
	)
	let temporary = files.temporaryDirectory.appendingPathComponent(
		"stana-input-\(ProcessInfo.processInfo.processIdentifier)-\(ResourceToken().rawValue)"
	)
	let app = temporary.appendingPathComponent("StanaInputProbe.app")
	let contents = app.appendingPathComponent("Contents")
	let binaries = contents.appendingPathComponent("MacOS")
	let resources = contents.appendingPathComponent("Resources")
	try files.createDirectory(at: binaries, withIntermediateDirectories: true)
	try files.createDirectory(at: resources, withIntermediateDirectories: true)
	defer {
		try? files.removeItem(at: temporary)
	}

	try files.copyItem(at: executable, to: binaries.appendingPathComponent("NativeInputProbe"))
	for bundle in try files.contentsOfDirectory(
		at: executable.deletingLastPathComponent(),
		includingPropertiesForKeys: nil
	)
	where bundle.pathExtension == "bundle" {
		try files.copyItem(at: bundle, to: resources.appendingPathComponent(bundle.lastPathComponent))
	}

	let info: [String: Any] = [
		"CFBundleExecutable": "NativeInputProbe", "CFBundleName": "StanaInputProbe",
		"CFBundleIdentifier": "dev.stana.input-probe", "CFBundlePackageType": "APPL",
		"CFBundleVersion": "1", "LSMinimumSystemVersion": "26.0", "NSHighResolutionCapable": true,
	]
	try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
		.write(to: contents.appendingPathComponent("Info.plist"))
	let output = temporary.appendingPathComponent("stdout.log")
	let errors = temporary.appendingPathComponent("stderr.log")
	let process = Process()
	process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
	process.arguments = [
		"-W", "-n", "--stdout", output.path, "--stderr", errors.path, app.path,
	]
	try process.run()
	for _ in 0..<9_000 {
		if !process.isRunning {
			break
		}

		try await Task.sleep(for: .milliseconds(10))
	}

	if process.isRunning {
		process.terminate()
	}

	try #require(!process.isRunning, "Foreground input probe timed out")
	let stdout = (try? String(contentsOf: output, encoding: .utf8)) ?? ""
	let stderr = (try? String(contentsOf: errors, encoding: .utf8)) ?? ""
	#expect(process.terminationStatus == 0)
	#expect(stdout.contains("Input-readiness qualification passed: 8/8"), "\(stdout)\n\(stderr)")
	#expect(stdout.components(separatedBy: "First-click PASS:").count - 1 == 8)
}
