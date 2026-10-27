import Foundation
import StanaPrimitives

/// Feature-based options. A host ignores features it cannot implement; it must
/// describe those decisions in its resolution rather than inventing support.
public struct STNWindowOptions: Equatable, Sendable {
    public enum Role: Int32, Sendable { case window, panel, utility, hud, nonactivatingPanel }
    public enum Frame: Int32, Sendable { case automatic, system, frameless }
    public enum Preference: Int32, Sendable { case automatic, enabled, disabled }
    public enum AppearancePreference: Int32, Sendable { case automatic, light, dark }
    public enum Separator: Int32, Sendable { case automatic, none, line, shadow }
    public enum Level: Equatable, Sendable {
        case automatic, normal, floating, modalPanel, mainMenu, status, popUpMenu, screenSaver
        case custom(Int32)
    }
    public enum Animation: Int32, Sendable { case automatic, none, document, utility, alert }
    public enum SpaceMembership: Int32, Sendable { case automatic, all, active }
    public enum Management: Int32, Sendable { case automatic, managed, transient, stationary }
    public enum ApplicationMembership: Int32, Sendable { case automatic, primary, auxiliary, all }
    public enum FullscreenRole: Int32, Sendable { case automatic, primary, auxiliary, none }
    public enum Tabbing: Int32, Sendable { case automatic, preferred, disallowed }
    public enum ToolbarStyle: Int32, Sendable { case automatic, expanded, preference, unified, unifiedCompact }
    public enum ToolbarDisplay: Int32, Sendable { case automatic, iconAndLabel, iconOnly, labelOnly }

    public struct Creation: Equatable, Sendable {
        public var role: Role
        public var identifier: String?
        public var initialOrigin: STNPoint?
        public var screenID: String?
        public var frameAutosaveName: String?
        public var initiallyVisible: Bool
        public var activatesOnOpen: Bool
        public init(
            role: Role = .window, identifier: String? = nil, initialOrigin: STNPoint? = nil,
            screenID: String? = nil, frameAutosaveName: String? = nil,
            initiallyVisible: Bool = true, activatesOnOpen: Bool = true
        ) {
            self.role = role
            self.identifier = identifier
            self.initialOrigin = initialOrigin
            self.screenID = screenID
            self.frameAutosaveName = frameAutosaveName
            self.initiallyVisible = initiallyVisible
            self.activatesOnOpen = activatesOnOpen
        }
    }
    public struct Appearance: Equatable, Sendable {
        public var frame: Frame
        public var background: STNColor
        public var opacity: Double
        public var shadow: Preference
        public var preference: AppearancePreference
        public init(
            frame: Frame = .automatic, background: STNColor = .background,
            opacity: Double = 1, shadow: Preference = .automatic,
            preference: AppearancePreference = .automatic
        ) {
            self.frame = frame
            self.background = background
            self.opacity = opacity
            self.shadow = shadow
            self.preference = preference
        }
    }
    public struct Button: Equatable, Sendable {
        public var visibility: Preference
        public var enabled: Preference
        public init(visibility: Preference = .automatic, enabled: Preference = .automatic) {
            self.visibility = visibility
            self.enabled = enabled
        }
    }
    public struct TitleBar: Equatable, Sendable {
        public var subtitle: String
        public var titleVisibility: Preference
        public var transparent: Preference
        public var fullSizeContent: Preference
        public var separator: Separator
        public var closeButton: Button
        public var minimizeButton: Button
        public var zoomButton: Button
        public var contentBorder: STNInsets?
        public init(
            subtitle: String = "", titleVisibility: Preference = .automatic,
            transparent: Preference = .automatic, fullSizeContent: Preference = .automatic,
            separator: Separator = .automatic, closeButton: Button = .init(),
            minimizeButton: Button = .init(), zoomButton: Button = .init(),
            contentBorder: STNInsets? = nil
        ) {
            self.subtitle = subtitle
            self.titleVisibility = titleVisibility
            self.transparent = transparent
            self.fullSizeContent = fullSizeContent
            self.separator = separator
            self.closeButton = closeButton
            self.minimizeButton = minimizeButton
            self.zoomButton = zoomButton
            self.contentBorder = contentBorder
        }
    }
    public struct Resizing: Equatable, Sendable {
        public var isResizable: Bool
        public var minimumContentSize: STNSize?
        public var maximumContentSize: STNSize?
        public var minimumFrameSize: STNSize?
        public var maximumFrameSize: STNSize?
        public var frameAspectRatio: STNSize?
        public var frameResizeIncrements: STNSize?
        public var contentAspectRatio: STNSize?
        public var contentResizeIncrements: STNSize?
        public var minimumFullscreenContentSize: STNSize?
        public var maximumFullscreenContentSize: STNSize?
        public var preservesContentDuringLiveResize: Preference
        public init(
            isResizable: Bool = true, minimumContentSize: STNSize? = nil,
            maximumContentSize: STNSize? = nil, minimumFrameSize: STNSize? = nil,
            maximumFrameSize: STNSize? = nil, frameAspectRatio: STNSize? = nil,
            frameResizeIncrements: STNSize? = nil, contentAspectRatio: STNSize? = nil,
            contentResizeIncrements: STNSize? = nil, minimumFullscreenContentSize: STNSize? = nil,
            maximumFullscreenContentSize: STNSize? = nil,
            preservesContentDuringLiveResize: Preference = .automatic
        ) {
            self.isResizable = isResizable
            self.minimumContentSize = minimumContentSize
            self.maximumContentSize = maximumContentSize
            self.minimumFrameSize = minimumFrameSize
            self.maximumFrameSize = maximumFrameSize
            self.frameAspectRatio = frameAspectRatio
            self.frameResizeIncrements = frameResizeIncrements
            self.contentAspectRatio = contentAspectRatio
            self.contentResizeIncrements = contentResizeIncrements
            self.minimumFullscreenContentSize = minimumFullscreenContentSize
            self.maximumFullscreenContentSize = maximumFullscreenContentSize
            self.preservesContentDuringLiveResize = preservesContentDuringLiveResize
        }
    }
    public struct Interaction: Equatable, Sendable {
        public var isMovable: Bool
        public var backgroundDragging: Bool
        public var ignoresMouseEvents: Bool
        public var acceptsMouseMovedEvents: Bool
        public var canBecomeKey: Preference
        public var canBecomeMain: Preference
        public var becomesKeyOnlyIfNeeded: Preference
        public var allowsInactiveTooltips: Preference
        public init(
            isMovable: Bool = true, backgroundDragging: Bool = false,
            ignoresMouseEvents: Bool = false, acceptsMouseMovedEvents: Bool = true,
            canBecomeKey: Preference = .automatic, canBecomeMain: Preference = .automatic,
            becomesKeyOnlyIfNeeded: Preference = .automatic,
            allowsInactiveTooltips: Preference = .automatic
        ) {
            self.isMovable = isMovable
            self.backgroundDragging = backgroundDragging
            self.ignoresMouseEvents = ignoresMouseEvents
            self.acceptsMouseMovedEvents = acceptsMouseMovedEvents
            self.canBecomeKey = canBecomeKey
            self.canBecomeMain = canBecomeMain
            self.becomesKeyOnlyIfNeeded = becomesKeyOnlyIfNeeded
            self.allowsInactiveTooltips = allowsInactiveTooltips
        }
    }
    public struct Behavior: Equatable, Sendable {
        public var level: Level
        public var animation: Animation
        public var canClose: Bool
        public var canMinimize: Bool
        public var hidesOnDeactivate: Preference
        public var canHide: Preference
        public var floatingPanel: Preference
        public var worksWhenModal: Preference
        public var preventsTerminationWhenModal: Preference
        public var excludedFromWindowsMenu: Bool
        public var canBecomeVisibleWithoutLogin: Bool
        public init(
            level: Level = .automatic, animation: Animation = .automatic, canClose: Bool = true,
            canMinimize: Bool = true, hidesOnDeactivate: Preference = .automatic,
            canHide: Preference = .automatic, floatingPanel: Preference = .automatic,
            worksWhenModal: Preference = .automatic, preventsTerminationWhenModal: Preference = .automatic,
            excludedFromWindowsMenu: Bool = false, canBecomeVisibleWithoutLogin: Bool = false
        ) {
            self.level = level
            self.animation = animation
            self.canClose = canClose
            self.canMinimize = canMinimize
            self.hidesOnDeactivate = hidesOnDeactivate
            self.canHide = canHide
            self.floatingPanel = floatingPanel
            self.worksWhenModal = worksWhenModal
            self.preventsTerminationWhenModal = preventsTerminationWhenModal
            self.excludedFromWindowsMenu = excludedFromWindowsMenu
            self.canBecomeVisibleWithoutLogin = canBecomeVisibleWithoutLogin
        }
    }
    public struct Workspaces: Equatable, Sendable {
        public var spaces: SpaceMembership
        public var management: Management
        public var applicationMembership: ApplicationMembership
        public var participatesInCycle: Preference
        public var fullscreen: FullscreenRole
        public var allowsTiling: Preference
        public var tabbing: Tabbing
        public var tabbingIdentifier: String
        public init(
            spaces: SpaceMembership = .automatic, management: Management = .automatic,
            applicationMembership: ApplicationMembership = .automatic,
            participatesInCycle: Preference = .automatic, fullscreen: FullscreenRole = .automatic,
            allowsTiling: Preference = .automatic, tabbing: Tabbing = .automatic,
            tabbingIdentifier: String = ""
        ) {
            self.spaces = spaces
            self.management = management
            self.applicationMembership = applicationMembership
            self.participatesInCycle = participatesInCycle
            self.fullscreen = fullscreen
            self.allowsTiling = allowsTiling
            self.tabbing = tabbing
            self.tabbingIdentifier = tabbingIdentifier
        }
    }
    public struct SystemIntegration: Equatable, Sendable {
        public var representedURL: URL?
        public var isDocumentEdited: Bool
        public var minimizedTitle: String?
        public var minimizedImage: Data?
        public var dockBadge: String?
        public var tabTitle: String?
        public var tabTooltip: String?
        public init(
            representedURL: URL? = nil, isDocumentEdited: Bool = false,
            minimizedTitle: String? = nil, minimizedImage: Data? = nil, dockBadge: String? = nil,
            tabTitle: String? = nil, tabTooltip: String? = nil
        ) {
            self.representedURL = representedURL
            self.isDocumentEdited = isDocumentEdited
            self.minimizedTitle = minimizedTitle
            self.minimizedImage = minimizedImage
            self.dockBadge = dockBadge
            self.tabTitle = tabTitle
            self.tabTooltip = tabTooltip
        }
    }
    public var creation: Creation
    public var appearance: Appearance
    public var titleBar: TitleBar
    public var resizing: Resizing
    public var interaction: Interaction
    public var behavior: Behavior
    public var workspaces: Workspaces
    public var systemIntegration: SystemIntegration
    public init(
        creation: Creation = .init(), appearance: Appearance = .init(), titleBar: TitleBar = .init(),
        resizing: Resizing = .init(), interaction: Interaction = .init(), behavior: Behavior = .init(),
        workspaces: Workspaces = .init(), systemIntegration: SystemIntegration = .init()
    ) {
        self.creation = creation
        self.appearance = appearance
        self.titleBar = titleBar
        self.resizing = resizing
        self.interaction = interaction
        self.behavior = behavior
        self.workspaces = workspaces
        self.systemIntegration = systemIntegration
    }
    public func validate() throws {
        func valid(_ s: STNSize) -> Bool { s.width.isFinite && s.height.isFinite && s.width >= 0 && s.height >= 0 }
        let sizes = [
            resizing.minimumContentSize, resizing.maximumContentSize, resizing.minimumFrameSize,
            resizing.maximumFrameSize, resizing.contentAspectRatio, resizing.contentResizeIncrements,
            resizing.frameAspectRatio, resizing.frameResizeIncrements,
            resizing.minimumFullscreenContentSize, resizing.maximumFullscreenContentSize,
        ].compactMap { $0 }
        guard sizes.allSatisfy(valid), appearance.opacity.isFinite, (0...1).contains(appearance.opacity),
            creation.initialOrigin.map({ $0.x.isFinite && $0.y.isFinite }) ?? true
        else {
            throw STNWindowError.invalidConfiguration("Geometry must be finite; opacity must be in 0...1")
        }
        for (lo, hi) in [
            (resizing.minimumContentSize, resizing.maximumContentSize),
            (resizing.minimumFrameSize, resizing.maximumFrameSize),
            (resizing.minimumFullscreenContentSize, resizing.maximumFullscreenContentSize),
        ] {
            if let lo, let hi, lo.width > hi.width || lo.height > hi.height {
                throw STNWindowError.invalidConfiguration("Minimum size exceeds maximum size")
            }
        }
        if [
            resizing.contentAspectRatio, resizing.contentResizeIncrements, resizing.frameAspectRatio,
            resizing.frameResizeIncrements,
        ].compactMap({ $0 }).count > 1 {
            throw STNWindowError.invalidConfiguration("Choose either an aspect ratio or resize increments")
        }
        for maximum in [resizing.maximumContentSize, resizing.maximumFrameSize, resizing.maximumFullscreenContentSize]
            .compactMap({ $0 })
        {
            guard maximum.width > 0 && maximum.height > 0 else {
                throw STNWindowError.invalidConfiguration("Maximum dimensions must be positive")
            }
        }
        for s in [
            resizing.contentAspectRatio, resizing.contentResizeIncrements, resizing.frameAspectRatio,
            resizing.frameResizeIncrements,
        ].compactMap({ $0 }) {
            guard s.width > 0 && s.height > 0 else {
                throw STNWindowError.invalidConfiguration("Ratios and increments must be positive")
            }
        }
        if let border = titleBar.contentBorder,
            ![border.top, border.leading, border.bottom, border.trailing].allSatisfy({ $0.isFinite && $0 >= 0 })
        {
            throw STNWindowError.invalidConfiguration("Content border must be finite and nonnegative")
        }
        if let image = systemIntegration.minimizedImage, image.count > 32 * 1024 * 1024 {
            throw STNWindowError.invalidConfiguration("Minimized image exceeds 32 MiB")
        }
    }
}

public enum STNWindowError: Error, Equatable, Sendable {
    case invalidConfiguration(String)
    case unsupportedAction(String)
    case invalidState(String)
    case invalidRelationship
    case closed, cancelled
    case nativeFailure(String)
}

public struct STNWindowResolution: Equatable, Sendable {
    public enum Reason: String, Sendable { case unsupported, inapplicable, requiresReopen }
    public struct Ignored: Equatable, Sendable {
        public let feature: String
        public let reason: Reason
        public init(_ feature: String, reason: Reason) {
            self.feature = feature
            self.reason = reason
        }
    }
    public var ignored: [Ignored]
    public var isPending: Bool
    public init(ignored: [Ignored] = [], isPending: Bool = false) {
        self.ignored = ignored
        self.isPending = isPending
    }
}

public struct STNWindowState: Equatable, Sendable {
    public enum FullscreenTransition: Int32, Sendable { case idle, entering, exiting }
    public var isOpen = false
    public var isVisible = false
    public var isKey = false
    public var isMain = false
    public var isMinimized = false
    public var isZoomed = false
    public var isFullscreen = false
    public var fullscreenTransition = FullscreenTransition.idle
    public var isInLiveResize = false
    public var isOnActiveSpace = false
    public var isOccluded = false
    public var hasSheet = false
    public var isSheet = false
    public var frame = STNRect.zero
    public var contentSize = STNSize.zero
    /// Top-left-origin bounds in the drawing surface, excluding native chrome.
    public var safeContentBounds = STNRect.zero
    public var scale: Double = 1
    public var screenID: String?
    public var parentID: UInt64?
    public var childIDs: [UInt64] = []
    public var tabIDs: [UInt64] = []
    public var nativeID: UInt64 = 0
    public var hasActiveSharingSession = false
    public var selectedTabID: UInt64?
    public var isTabBarVisible = false
    public var isTabOverviewVisible = false
    public init() {}
}

package enum WindowAction: Int32, Sendable {
    case show = 1
    case showInactive, hide, focus, center, minimize, restore, zoom, orderFront, orderBack
    case requestClose, enterFullscreen, exitFullscreen, customizeToolbar, toggleToolbar
    case nextTab, previousTab, moveTabToWindow, mergeWindows, toggleTabBar, toggleTabOverview
}
package enum WindowRelationship: Int32 {
    case childAbove = 1
    case childBelow, detach, tabBefore, tabAfter, selectTab, detachTab
}

@MainActor package struct WindowToolbar {
    package var identifier: String
    package var allowsCustomization: Bool
    package var autosavesConfiguration: Bool
    package var defaultIdentifiers: [String]
    package var items: [WindowToolbarItem]
    package init(
        identifier: String, allowsCustomization: Bool, autosavesConfiguration: Bool,
        defaultIdentifiers: [String], items: [WindowToolbarItem]
    ) {
        self.identifier = identifier
        self.allowsCustomization = allowsCustomization
        self.autosavesConfiguration = autosavesConfiguration
        self.defaultIdentifiers = defaultIdentifiers
        self.items = items
    }
}
@MainActor package struct WindowToolbarItem {
    package var identifier: String
    package var kind: Int32
    package var command: UInt64 = 0
    package var title: String = ""
    package var enabled = true
    package var checked = false
    package var image: Data?
    package var tooltip: String?
    package var priority: Int32 = 0
    package var children: [WindowToolbarItem] = []
    package var surface: (any PlatformWindow)?
    package init(identifier: String, kind: Int32) {
        self.identifier = identifier
        self.kind = kind
    }
}
@MainActor package struct WindowAccessory {
    package var identifier: String
    package var placement: Int32
    package var fullscreenMinimumHeight: Double
    package var hidden: Bool
    package var surface: any PlatformWindow
    package init(
        identifier: String, placement: Int32, fullscreenMinimumHeight: Double, hidden: Bool, surface: any PlatformWindow
    ) {
        self.identifier = identifier
        self.placement = placement
        self.fullscreenMinimumHeight = fullscreenMinimumHeight
        self.hidden = hidden
        self.surface = surface
    }
}

public struct STNScreen: Equatable, Sendable {
    public let id: String
    public let name: String
    public let frame: STNRect
    public let visibleFrame: STNRect
    public let scale: Double
    public init(id: String, name: String, frame: STNRect, visibleFrame: STNRect, scale: Double) {
        self.id = id
        self.name = name
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.scale = scale
    }
}
