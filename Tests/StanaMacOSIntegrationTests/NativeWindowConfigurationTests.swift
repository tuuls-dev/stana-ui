import CStanaMacOS
import Foundation
import Stana
import StanaPlatform
import StanaPrimitives
import Testing

@testable import StanaPlatformMacOS

@Suite(.enabled(if: ProcessInfo.processInfo.environment["STANA_GUI_TESTS"] == "1"), .serialized)
@MainActor struct NativeWindowConfigurationTests {
	@Test func defaultAndFramelessStylesHaveWorkingKeyboardEligibility() throws {
		let standard = try MacOSWindow(title: "Standard", size: .init(width: 360, height: 240))
		defer {
			standard.close()
		}

		#expect(stn_window_test_style(standard.handle) & 15 == 15)
		let options = STNWindowOptions(appearance: .init(frame: .frameless), resizing: .init(isResizable: false))
		let frameless = try MacOSWindow(title: "Frameless", size: .init(width: 360, height: 240), options: options)
		defer {
			frameless.close()
		}

		#expect(stn_window_test_style(frameless.handle) & 1 == 0)
		#expect(stn_window_test_style(frameless.handle) & 8 == 0)
		#expect(stn_window_test_property(frameless.handle, 2) == 1)
		#expect(stn_window_test_property(frameless.handle, 3) == 1)
		try frameless.perform(.show)
		frameless.editing(true)
		"c".withNativeUTF8 { #expect(stn_window_test_key_equivalent(frameless.handle, $0)) }
	}

	@Test func panelRoleIsNativeAndUnavailablePanelOptionsAreResolved() throws {
		let options = STNWindowOptions(
			creation: .init(role: .nonactivatingPanel),
			interaction: .init(becomesKeyOnlyIfNeeded: .enabled),
			behavior: .init(floatingPanel: .enabled, worksWhenModal: .enabled)
		)
		let panel = try MacOSWindow(title: "Panel", size: .init(width: 280, height: 160), options: options)
		defer {
			panel.close()
		}

		#expect(stn_window_test_property(panel.handle, 4) == 1)
		#expect(stn_window_test_property(panel.handle, 3) == 0)
		#expect(stn_window_test_style(panel.handle) & (1 << 7) != 0)
		let resolved = try MacOSHost().resolve(.init(behavior: .init(worksWhenModal: .enabled)), initial: nil)
		#expect(resolved.options.behavior.worksWhenModal == .automatic)
		#expect(resolved.resolution.ignored == [.init("behavior.worksWhenModal", reason: .inapplicable)])
	}

	@Test func reactiveChromeKeepsNativeSurfaceDocumentAndEditorIdentity() throws {
		let text = STNSignal("Editing")
		let config = STNSignal(STNWindow.Configuration())
		let window = STNWindow(
			properties: .init(title: "Live chrome", size: .init(width: 400, height: 260), configuration: config)
		) {
			STNTextField(properties: .init(value: text.binding))
		}
		try STNApplication.open(window)
		defer {
			window.close()
		}

		let session = try #require(window.session)
		let native = try #require(session.window as? MacOSWindow)
		let handle = native.handle
		let ids = session.nodeSnapshots.map(\.id)
		let editor = try #require(session.nodeSnapshots.first { $0.kind == "textField" })
		session.document.setFocus(editor.id)
		config.value.appearance.frame = .frameless
		#expect(native.handle == handle)
		#expect(session.nodeSnapshots.map(\.id) == ids)
		#expect(session.document.focused == editor.id)
		#expect(stn_window_test_style(native.handle) & 1 == 0)
		config.value.appearance.frame = .system
		config.value.titleBar.fullSizeContent = .enabled
		config.value.titleBar.transparent = .enabled
		config.value.titleBar.closeButton.visibility = .disabled
		#expect(stn_window_test_style(native.handle) & (1 << 15) != 0)
		#expect(stn_window_test_property(native.handle, 9) == 1)
		#expect(window.state.value.safeContentBounds.minY > 0)
		#expect(session.errors.isEmpty)
	}

	@Test func nativeConstraintsAndOpacityAreAppliedAndReset() throws {
		let window = try MacOSWindow(
			title: "Constraints",
			size: .init(width: 400, height: 300),
			options: .init(
				appearance: .init(opacity: 0.75, shadow: .disabled),
				resizing: .init(
					minimumContentSize: .init(width: 240, height: 160),
					maximumContentSize: .init(width: 600, height: 500)
				)
			)
		)
		defer {
			window.close()
		}

		#expect(stn_window_test_property(window.handle, 5) == 240)
		#expect(stn_window_test_property(window.handle, 6) == 160)
		#expect(stn_window_test_property(window.handle, 7) == 0.75)
		#expect(stn_window_test_property(window.handle, 8) == 0)
		try window.setContentSize(.init(width: 100, height: 100))
		#expect(window.state.contentSize.width >= 240)
		#expect(window.state.contentSize.height >= 160)
		try window.apply(.init())
		#expect(stn_window_test_property(window.handle, 7) == 1)
		#expect(stn_window_test_property(window.handle, 8) == 1)
		#expect(stn_window_test_property(window.handle, 5) == 0)
	}

	@Test func transparentRasterHasAlphaInsteadOfOpaqueRootFill() throws {
		let window = STNWindow(
			properties: .init(
				title: "Transparent raster",
				size: .init(width: 160, height: 120),
				configuration: .init(appearance: .init(frame: .frameless, background: .clear))
			)
		) {}
		try STNApplication.open(window)
		defer {
			window.close()
		}

		let session = try #require(window.session)
		let native = try #require(session.window as? MacOSWindow)
		session.draw()
		#expect(stn_window_test_property(native.handle, 1) == 0)
		#expect(stn_window_pixel_hash(native.handle) != 0)
		#expect(stn_window_export_png(native.handle, "/tmp/stana-transparent-window.png"))
	}

	@Test func nativeToolbarAndAccessorySurfacesPreserveIdentity() throws {
		let title = STNSignal("Action")
		let command = STNCommand(properties: .init(title: title, onActivate: {}))
		var mounts = 0
		let custom = STNToolbarContent(identifier: "custom", size: .init(width: 100, height: 28)) {
			STNButton(properties: .init(text: "Custom", onMount: { _ in mounts += 1 }, onActivate: {}))
		}
		let toolbar = STNToolbar(properties: .init(identifier: "stana.verification", allowsCustomization: true)) {
			STNToolbar.Item.command(id: "action", command)
			STNToolbar.Item.flexibleSpace(id: "space")
			STNToolbar.Item.content(custom)
		}
		let accessory = STNTitlebarAccessory(
			properties: .init(identifier: "status", size: .init(width: 120, height: 24), placement: .bottom)
		) {
			STNText(properties: .init(text: "Accessory", onMount: { _ in mounts += 1 }))
		}
		let config = STNSignal(STNWindow.Configuration(chrome: .init(toolbar: toolbar, accessories: [accessory])))
		let window = STNWindow(
			properties: .init(title: "Chrome surfaces", size: .init(width: 500, height: 320), configuration: config)
		) {}
		try STNApplication.open(window)
		defer {
			window.close()
		}

		let native = try #require(window.session?.window as? MacOSWindow)
		#expect(stn_window_test_property(native.handle, 14) == 3)
		#expect(stn_window_test_property(native.handle, 15) == 1)
		#expect(mounts == 2)
		config.value.chrome.toolbarStyle = .unifiedCompact
		title.value = "Updated"
		#expect(mounts == 2)
		#expect(window.session?.errors.isEmpty == true)
		config.value.chrome = .init()
		#expect(stn_window_test_property(native.handle, 14) == 0)
		#expect(stn_window_test_property(native.handle, 15) == 0)
	}

	@Test func nativeRelationshipsAndCloseVetoAreHonored() throws {
		let parent = STNWindow(properties: .init(title: "Parent", shouldClose: { false })) {}
		let child = STNWindow(properties: .init(title: "Child")) {}
		try STNApplication.open(parent)
		try STNApplication.open(child)
		defer {
			parent.close()
			child.close()
		}

		try parent.requestClose()
		#expect(parent.isOpen)
		try parent.addChild(child)
		#expect(child.state.value.parentID == parent.state.value.nativeID)
		try parent.removeChild(child)
		#expect(child.state.value.parentID == nil)
		try parent.addTabbedWindow(child)
		#expect(parent.state.value.tabIDs.count == 2)
		#expect(child.state.value.tabIDs == parent.state.value.tabIDs)
	}

	@Test func unsupportedActionsFailRatherThanSucceedingSilently() async throws {
		let window = try MacOSWindow(
			title: "No fullscreen",
			size: .init(width: 240, height: 160),
			options: .init(appearance: .init(frame: .frameless), workspaces: .init(fullscreen: .none))
		)
		defer {
			window.close()
		}

		do {
			try await window.setFullscreen(true)
			Issue.record("Borderless fullscreen unexpectedly succeeded")
		} catch {
			let failure = error as? STNWindowError
			#expect(failure != nil)
		}
	}

	@Test func sheetResultAndParentClosureCompleteOutstandingOperations() async throws {
		let parent = STNWindow(properties: .init(title: "Sheet parent", size: .init(width: 480, height: 320))) {}
		let sheet = STNWindow(properties: .init(title: "Sheet", size: .init(width: 280, height: 160))) {}
		try STNApplication.open(parent)
		defer {
			parent.close()
			sheet.close()
		}

		let result = Task { @MainActor in try await parent.presentSheet(sheet) }
		for _ in 0..<100 {
			if sheet.state.value.isSheet {
				break
			}

			try await Task.sleep(for: .milliseconds(10))
		}

		guard sheet.state.value.isSheet else {
			result.cancel()
			_ = await result.result
			Issue.record("Sheet did not attach")
			return
		}

		try sheet.endSheet(result: 42)
		#expect(try await result.value == 42)
		#expect(!sheet.isOpen)
		let again = Task { @MainActor in try await parent.presentSheet(sheet) }
		for _ in 0..<100 {
			if sheet.state.value.isSheet {
				break
			}

			try await Task.sleep(for: .milliseconds(10))
		}

		parent.close()
		let completion = await again.result
		if case .success = completion {
			Issue.record("Closing parent should cancel pending sheet operation")
		}

		#expect(!sheet.isOpen)
	}

	@Test func savedGeometryAndDisplayDiscoveryUsePortableCoordinates() throws {
		let name = "stana.test." + UUID().uuidString
		defer {
			STNApplication.removeSavedWindowFrame(named: name)
		}

		let window = STNWindow(properties: .init(title: "Persisted geometry", size: .init(width: 400, height: 300))) {}
		try STNApplication.open(window)
		defer {
			window.close()
		}

		#expect(!STNApplication.screens.isEmpty)
		#expect(STNApplication.screens.contains { $0.id == window.state.value.screenID })
		let original = window.state.value.contentSize
		try window.saveFrame(named: name)
		try window.setContentSize(.init(width: 520, height: 360))
		#expect(try window.restoreFrame(named: name))
		#expect(window.state.value.contentSize == original)
	}

	@Test func crossSpaceChromeTransitionsAwaitNativeCompletion() async throws {
		let window = STNWindow(
			properties: .init(
				title: "Fullscreen transition",
				size: .init(width: 480, height: 320),
				configuration: .init(workspaces: .init(fullscreen: .primary))
			)
		) {}
		try STNApplication.open(window)
		defer {
			window.close()
		}

		let entering = Task { @MainActor in try await window.setFullscreen(true) }
		for _ in 0..<500 {
			if window.state.value.isFullscreen && window.state.value.fullscreenTransition == .idle {
				break
			}

			try await Task.sleep(for: .milliseconds(10))
		}

		guard window.state.value.isFullscreen && window.state.value.fullscreenTransition == .idle else {
			entering.cancel()
			_ = await entering.result
			Issue.record("Native fullscreen did not complete within five seconds")
			return
		}

		try await entering.value
		let exiting = Task { @MainActor in try await window.setFullscreen(false) }
		for _ in 0..<500 {
			if !window.state.value.isFullscreen && window.state.value.fullscreenTransition == .idle {
				break
			}

			try await Task.sleep(for: .milliseconds(10))
		}

		guard !window.state.value.isFullscreen && window.state.value.fullscreenTransition == .idle else {
			exiting.cancel()
			_ = await exiting.result
			Issue.record("Native fullscreen exit did not complete within five seconds")
			return
		}

		try await exiting.value
	}

	@Test func contentAndFrameAspectPoliciesConstrainDifferentGeometry() throws {
		let content = try MacOSWindow(
			title: "Content aspect",
			size: .init(width: 400, height: 300),
			options: .init(
				resizing: .init(contentAspectRatio: .init(width: 2, height: 1))
			)
		)
		defer {
			content.close()
		}

		try content.setContentSize(.init(width: 500, height: 400))
		#expect(abs(content.state.contentSize.width / content.state.contentSize.height - 2) < 0.001)
		let frame = try MacOSWindow(
			title: "Frame aspect",
			size: .init(width: 400, height: 300),
			options: .init(
				resizing: .init(frameAspectRatio: .init(width: 2, height: 1))
			)
		)
		defer {
			frame.close()
		}

		try frame.setFrame(.init(x: 100, y: 100, width: 500, height: 400), animate: false)
		#expect(abs(frame.state.frame.size.width / frame.state.frame.size.height - 2) < 0.001)
		let before = frame.state.frame
		var impossible = STNWindowOptions()
		impossible.resizing.minimumContentSize = .init(width: 600, height: 400)
		impossible.resizing.maximumFrameSize = .init(width: 100, height: 100)
		#expect(throws: STNWindowError.self) { try frame.apply(impossible) }
		#expect(frame.state.frame == before)
		#expect(throws: STNWindowError.self) {
			_ = try MacOSWindow(title: "Invalid allocation", size: .init(width: 400, height: 300), options: impossible)
		}
	}

	@Test func accessoryEditorCompositionDefersChromeAndRetainsNativeFocus() throws {
		let value = STNSignal("A")
		var mounts = 0
		let accessory = STNTitlebarAccessory(
			properties: .init(identifier: "editor", size: .init(width: 200, height: 30), placement: .bottom)
		) {
			STNTextField(
				properties: .init(
					value: value.binding,
					onMount: { handle in
						mounts += 1
						try? handle.requestFocus()
					}
				)
			)
		}
		let config = STNSignal(STNWindow.Configuration(chrome: .init(accessories: [accessory])))
		let window = STNWindow(
			properties: .init(
				title: "Accessory composition",
				size: .init(width: 500, height: 320),
				configuration: config
			)
		) {}
		try STNApplication.open(window)
		defer {
			window.close()
		}

		let native = try #require(window.session?.window as? MacOSWindow)
		"に".withNativeUTF8 { #expect(stn_window_test_marked_text(native.handle, $0, false)) }
		config.value.titleBar.fullSizeContent = .enabled
		#expect(window.resolution.value.isPending)
		#expect(value.value == "A")
		"".withNativeUTF8 { #expect(stn_window_test_marked_text(native.handle, $0, true)) }
		#expect(!window.resolution.value.isPending)
		#expect(value.value.contains("に"))
		#expect(mounts == 1)
		"い".withNativeUTF8 { #expect(stn_window_test_marked_text(native.handle, $0, false)) }
		"".withNativeUTF8 { #expect(stn_window_test_marked_text(native.handle, $0, true)) }
		#expect(value.value.contains("い"))
	}
}
