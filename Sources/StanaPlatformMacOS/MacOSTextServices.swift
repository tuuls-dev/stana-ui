import CStanaMacOS
import Foundation

extension MacOSWindow {
	package var caretInterval: Double {
		stn_caret_interval(false)
	}

	package var caretOffInterval: Double {
		stn_caret_interval(true)
	}

	package func textServiceEnabled(_ feature: Int, policies: [Int32]) -> Bool {
		stn_text_service_enabled(Int32(feature), feature < policies.count ? policies[feature] : 0)
	}

	package func configureText(identity: UInt64, readOnly: Bool, canUndo: Bool, canRedo: Bool, policies: [Int32]) {
		guard let handle else {
			return
		}

		policies.withUnsafeBufferPointer {
			stn_window_text_options(handle, identity, readOnly, canUndo, canRedo, $0.baseAddress, $0.count)
		}
	}
}
