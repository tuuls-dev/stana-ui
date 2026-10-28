import StanaPlatform
import StanaPrimitives

extension STNWindow {
	/// One interface for every host. Unavailable features are ignored and
	/// described by `resolution`; malformed values are reported as errors.
	public struct Configuration: Equatable, Sendable {
		public typealias Creation = STNWindowOptions.Creation
		public typealias Appearance = STNWindowOptions.Appearance
		public typealias TitleBar = STNWindowOptions.TitleBar
		public typealias Resizing = STNWindowOptions.Resizing
		public typealias Interaction = STNWindowOptions.Interaction
		public typealias Behavior = STNWindowOptions.Behavior
		public typealias Workspaces = STNWindowOptions.Workspaces
		public typealias SystemIntegration = STNWindowOptions.SystemIntegration
		public typealias Preference = STNWindowOptions.Preference
		package var options: STNWindowOptions
		public var chrome: Chrome
		public var renderingColorMode: STNRenderingColorMode

		public var creation: Creation {
			get {
				options.creation
			}
			set {
				options.creation = newValue
			}
		}

		public var appearance: Appearance {
			get {
				options.appearance
			}
			set {
				options.appearance = newValue
			}
		}

		public var titleBar: TitleBar {
			get {
				options.titleBar
			}
			set {
				options.titleBar = newValue
			}
		}

		public var resizing: Resizing {
			get {
				options.resizing
			}
			set {
				options.resizing = newValue
			}
		}

		public var interaction: Interaction {
			get {
				options.interaction
			}
			set {
				options.interaction = newValue
			}
		}

		public var behavior: Behavior {
			get {
				options.behavior
			}
			set {
				options.behavior = newValue
			}
		}

		public var workspaces: Workspaces {
			get {
				options.workspaces
			}
			set {
				options.workspaces = newValue
			}
		}

		public var systemIntegration: SystemIntegration {
			get {
				options.systemIntegration
			}
			set {
				options.systemIntegration = newValue
			}
		}

		public init(
			creation: Creation = .init(),
			appearance: Appearance = .init(),
			titleBar: TitleBar = .init(),
			resizing: Resizing = .init(),
			interaction: Interaction = .init(),
			behavior: Behavior = .init(),
			workspaces: Workspaces = .init(),
			systemIntegration: SystemIntegration = .init(),
			chrome: Chrome = .init(),
			renderingColorMode: STNRenderingColorMode = .automatic
		) {
			options = .init(
				creation: creation,
				appearance: appearance,
				titleBar: titleBar,
				resizing: resizing,
				interaction: interaction,
				behavior: behavior,
				workspaces: workspaces,
				systemIntegration: systemIntegration
			)
			self.chrome = chrome
			self.renderingColorMode = renderingColorMode
		}
	}

	public struct Chrome: Equatable, Sendable {
		public var toolbar: STNToolbar?
		public var toolbarVisible: Bool
		public var toolbarStyle: STNWindowOptions.ToolbarStyle
		public var toolbarDisplay: STNWindowOptions.ToolbarDisplay
		public var accessories: [STNTitlebarAccessory]
		public var tabAccessory: STNToolbarContent?

		public init(
			toolbar: STNToolbar? = nil,
			toolbarVisible: Bool = true,
			toolbarStyle: STNWindowOptions.ToolbarStyle = .automatic,
			toolbarDisplay: STNWindowOptions.ToolbarDisplay = .automatic,
			accessories: [STNTitlebarAccessory] = [],
			tabAccessory: STNToolbarContent? = nil
		) {
			self.toolbar = toolbar
			self.toolbarVisible = toolbarVisible
			self.toolbarStyle = toolbarStyle
			self.toolbarDisplay = toolbarDisplay
			self.accessories = accessories
			self.tabAccessory = tabAccessory
		}
	}
}
