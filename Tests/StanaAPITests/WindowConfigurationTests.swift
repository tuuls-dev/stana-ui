import Foundation
import Stana
import StanaTesting
import Testing

@Suite @MainActor struct WindowConfigurationTests {
	@Test func reactiveConfigurationPreservesIdentityAndCancelsOnClose() throws {
		let config = STNSignal(STNWindow.Configuration())
		let title = STNSignal("Initial")
		let window = STNWindow(properties: .init(title: title, configuration: config)) {
			STNText(properties: .init(text: "Retained"))
		}
		let host = try STNWindowTestHost(window: window)
		let ids = host.nodes.map(\.id)
		let builders = host.metrics?.builderExecutions
		let before = host.applicationCount
		config.value.appearance.frame = .frameless
		title.value = "Updated"
		#expect(window.appliedConfiguration.value?.appearance.frame == .frameless)
		#expect(host.title == "Updated")
		#expect(host.nodes.map(\.id) == ids)
		#expect(host.metrics?.builderExecutions == builders)
		#expect(host.applicationCount == before + 1)
		config.value = config.value
		#expect(host.applicationCount == before + 1)
		host.close()
		let closedCount = host.applicationCount
		config.value.appearance.frame = .system
		title.value = "After close"
		#expect(host.applicationCount == closedCount)
		#expect(host.title == "Updated")
		#expect(!window.state.value.isOpen)
	}

	@Test func unsupportedFeaturesAreIgnoredWithoutDiscardingSupportedSettings() throws {
		let config = STNWindow.Configuration(
			creation: .init(role: .panel),
			appearance: .init(frame: .frameless, opacity: 0.4),
			titleBar: .init(subtitle: "Unsupported"),
			workspaces: .init(spaces: .all)
		)
		let window = STNWindow(properties: .init(title: "Portable", configuration: config)) {}
		let host = try STNWindowTestHost(window: window, unsupportedFeatures: [.panel, .frame, .titleBar, .workspaces])
		defer {
			host.close()
		}

		#expect(window.appliedConfiguration.value?.appearance.frame == .automatic)
		#expect(window.appliedConfiguration.value?.creation.role == .window)
		#expect(window.appliedConfiguration.value?.appearance.opacity == 0.4)
		#expect(window.resolution.value.ignored.count == 4)
		#expect(window.resolution.value.ignored.allSatisfy { $0.reason == .unsupported })
	}

	@Test func invalidUpdatesRetainLastGoodSnapshotAndInitialInvalidityThrows() throws {
		var errors: [STNWindowError] = []
		let config = STNSignal(STNWindow.Configuration())
		let window = STNWindow(
			properties: .init(title: "Validation", configuration: config, onConfigurationError: { errors.append($0) })
		) {}
		let host = try STNWindowTestHost(window: window)
		defer {
			host.close()
		}

		let count = host.applicationCount
		config.value.appearance.opacity = .nan
		#expect(errors.count == 1)
		#expect(window.appliedConfiguration.value?.appearance.opacity == 1)
		#expect(host.applicationCount == count)
		config.value = .init(
			resizing: .init(
				minimumContentSize: .init(width: 500, height: 400),
				maximumContentSize: .init(width: 100, height: 100)
			)
		)
		#expect(errors.count == 2)
		let bad = STNWindow(properties: .init(title: "Invalid", configuration: config)) {}
		#expect(throws: STNWindowError.self) { _ = try STNWindowTestHost(window: bad) }
		#expect(!bad.isOpen)
	}

	@Test func creationPolicyIsFrozenUntilReopenAndComputedInputsWork() throws {
		let role = STNSignal(false)
		let config = role.map { STNWindow.Configuration(creation: .init(role: $0 ? .panel : .window)) }
		let window = STNWindow(properties: .init(title: role.map { $0 ? "Panel" : "Window" }, configuration: config)) {}
		let first = try STNWindowTestHost(window: window)
		role.value = true
		#expect(window.appliedConfiguration.value?.creation.role == .window)
		#expect(window.resolution.value.ignored == [.init("creation", reason: .requiresReopen)])
		first.close()
		let second = try STNWindowTestHost(window: window)
		defer {
			second.close()
		}

		#expect(window.appliedConfiguration.value?.creation.role == .panel)
		#expect(window.resolution.value.ignored.isEmpty)
	}

	@Test func pendingChromeChangesCoalesceAndDoNotRemount() throws {
		let config = STNSignal(STNWindow.Configuration())
		let window = STNWindow(properties: .init(title: "Deferred", configuration: config)) {
			STNText(properties: .init(text: "Content"))
		}
		let host = try STNWindowTestHost(window: window)
		defer {
			host.close()
		}

		let ids = host.nodes.map(\.id)
		host.setBusy(true)
		config.value.appearance.frame = .frameless
		#expect(window.resolution.value.isPending)
		#expect(window.appliedConfiguration.value?.appearance.frame == .automatic)
		config.value.appearance.opacity = 0.5
		host.setBusy(false)
		#expect(!window.resolution.value.isPending)
		#expect(window.appliedConfiguration.value?.appearance.frame == .frameless)
		#expect(window.appliedConfiguration.value?.appearance.opacity == 0.5)
		#expect(host.nodes.map(\.id) == ids)
	}

	@Test func compositionDefersChromeWithoutCommittingOrLosingEditor() throws {
		let value = STNSignal("A")
		let config = STNSignal(STNWindow.Configuration())
		let window = STNWindow(properties: .init(title: "IME", configuration: config)) {
			STNTextField(properties: .init(value: value.binding))
		}
		let host = try STNWindowTestHost(window: window)
		defer {
			host.close()
		}

		let editor = try #require(host.nodes.first { $0.kind == "textField" })
		try host.focus(editor.id)
		host.setMarkedText("に", selectedRange: .init(location: 1, length: 0))
		config.value.appearance.frame = .frameless
		#expect(window.resolution.value.isPending)
		#expect(value.value == "A")
		host.commitMarkedText()
		#expect(!window.resolution.value.isPending)
		#expect(window.appliedConfiguration.value?.appearance.frame == .frameless)
		#expect(host.nodes.contains { $0.id == editor.id })
		#expect(value.value.contains("に"))
	}

	@Test func dragRegionsExcludeControlsHandlersAndExplicitExclusions() throws {
		var activations = 0
		let window = STNWindow(properties: .init(title: "Drag")) {
			STNWindowDragRegion(properties: .init(frame: .init(width: 400, height: 120))) {
				STNHStack {
					STNButton(properties: .init(text: "Close", onActivate: { activations += 1 }))
					STNWindowDragRegion(properties: .init(mode: .exclude, frame: .init(width: 70, height: 40))) {}
					STNBox(
						properties: .init(frame: .init(width: 70, height: 40), onPointerDown: { $0.preventDefault() })
					) {}
				}
			}
		}
		let host = try STNWindowTestHost(window: window)
		defer {
			host.close()
		}

		#expect(host.pointerDown(at: .init(x: 390, y: 100)) == 1)
		let button = try #require(host.nodes.first { $0.kind == "button" })
		let point = STNPoint(x: button.bounds.minX + 2, y: button.bounds.minY + 2)
		#expect(host.pointerDown(at: point) == 0)
		host.pointerUp(at: point)
		#expect(activations == 1)
		#expect(host.pointerDown(at: .init(x: button.bounds.maxX + 10, y: 10)) == 0)
		#expect(host.pointerDown(at: .init(x: button.bounds.maxX + 80, y: 10)) == 0)
		#expect(host.pointerDown(at: .init(x: 500, y: 200)) == 0)
	}

	@Test func resizeRegionsAndSafeContentLayoutFollowWindowState() throws {
		let window = STNWindow(properties: .init(title: "Layout", size: .init(width: 400, height: 300))) {
			STNWindowContent { STNText(properties: .init(text: "Safe")) }
		}
		let host = try STNWindowTestHost(window: window)
		defer {
			host.close()
		}

		host.setSafeContentBounds(.init(x: 0, y: 50, width: 400, height: 250))
		#expect(host.nodes.first { $0.kind == "text" }?.bounds.minY == 50)
		let gripWindow = STNWindow(properties: .init(title: "Resize")) {
			STNWindowResizeRegion(properties: .init(edges: [.bottom, .trailing], frame: .init(width: 20, height: 20))) {
			}
		}
		let grip = try STNWindowTestHost(window: gripWindow)
		defer {
			grip.close()
		}

		#expect(grip.pointerDown(at: .init(x: 5, y: 5)) == 28)
	}

	@Test func transparentSurfaceDoesNotPaintOpaqueDefaultBackground() throws {
		let window = STNWindow(
			properties: .init(
				title: "Transparent",
				configuration: .init(appearance: .init(frame: .frameless, background: .clear))
			)
		) {}
		let host = try STNWindowTestHost(window: window)
		defer {
			host.close()
		}

		let fills = host.renderedFillColors()
		#expect(fills == [.clear])
	}

	@Test func toolbarCommandsRemainSharedAndStableSurfacesAreNotRemounted() throws {
		let title = STNSignal("Save")
		var calls = 0
		var mounts = 0
		let command = STNCommand(properties: .init(title: title, onActivate: { calls += 1 }))
		let accessory = STNTitlebarAccessory(
			properties: .init(identifier: "status", size: .init(width: 120, height: 26))
		) {
			STNText(properties: .init(text: "Status", onMount: { _ in mounts += 1 }))
		}
		let toolbar = STNToolbar(properties: .init(identifier: "editor")) { .command(id: "save", command) }
		let config = STNSignal(STNWindow.Configuration(chrome: .init(toolbar: toolbar, accessories: [accessory])))
		let window = STNWindow(properties: .init(title: "Chrome", configuration: config)) {}
		let host = try STNWindowTestHost(window: window)
		defer {
			host.close()
		}

		#expect(host.toolbarTitles == ["Save"])
		host.performToolbarCommand(at: 0)
		#expect(calls == 1)
		title.value = "Save As"
		#expect(host.toolbarTitles == ["Save As"])
		config.value.chrome.toolbarVisible = false
		#expect(mounts == 1)
		#expect(host.chromeSurfaceCount == 1)
		config.value.chrome = .init()
		#expect(host.toolbarTitles.isEmpty)
	}

	@Test func userCloseIsVetoableButProgrammaticCloseIsImmediate() throws {
		let window = STNWindow(properties: .init(title: "Close", shouldClose: { false })) {}
		let host = try STNWindowTestHost(window: window)
		try window.requestClose()
		#expect(window.isOpen)
		window.close()
		#expect(!window.isOpen)
		#expect(throws: STNWindowError.closed) { try window.focus() }
		host.close()
	}

	@Test func relationshipsRejectCyclesAndParentClosureOwnsChildLifetime() throws {
		let parent = STNWindow(properties: .init(title: "Parent")) {}
		let child = STNWindow(properties: .init(title: "Child")) {}
		let p = try STNWindowTestHost(window: parent)
		let c = try STNWindowTestHost(window: child)
		try parent.addChild(child)
		#expect(child.state.value.parentID == parent.state.value.nativeID)
		#expect(throws: STNWindowError.invalidRelationship) { try child.addChild(parent) }
		p.close()
		#expect(!child.isOpen)
		c.close()
	}

	@Test func closingDuringMountDoesNotContinueNativeSetup() throws {
		final class Reference {
			weak var window: STNWindow?
		}

		let reference = Reference()
		var errors: [STNWindowError] = []
		let window = STNWindow(
			properties: .init(title: "Close during mount", onConfigurationError: { errors.append($0) })
		) {
			STNText(properties: .init(text: "Closing", onMount: { _ in reference.window?.close() }))
		}
		reference.window = window
		let host = try STNWindowTestHost(window: window)
		#expect(!window.isOpen)
		#expect(!window.state.value.isVisible)
		#expect(errors.isEmpty)
		host.close()
	}
}
