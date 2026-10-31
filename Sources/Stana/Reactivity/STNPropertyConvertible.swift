import StanaCore
import StanaPrimitives

extension String: STNPropertyConvertible {
	public func asProperty() -> STNProperty<String> {
		STNProperty(self)
	}
}

extension Bool: STNPropertyConvertible {
	public func asProperty() -> STNProperty<Bool> {
		STNProperty(self)
	}
}

extension Double: STNPropertyConvertible {
	public func asProperty() -> STNProperty<Double> {
		STNProperty(self)
	}
}

extension STNColor: STNPropertyConvertible {
	public func asProperty() -> STNProperty<STNColor> {
		STNProperty(self)
	}
}

extension STNFont: STNPropertyConvertible {
	public func asProperty() -> STNProperty<STNFont> {
		STNProperty(self)
	}
}

extension STNInsets: STNPropertyConvertible {
	public func asProperty() -> STNProperty<STNInsets> {
		STNProperty(self)
	}
}

extension STNFrame: STNPropertyConvertible {
	public func asProperty() -> STNProperty<STNFrame> {
		STNProperty(self)
	}
}

extension STNAffineTransform: STNPropertyConvertible {
	public func asProperty() -> STNProperty<STNAffineTransform> {
		STNProperty(self)
	}
}

extension STNBackdropEffect: STNPropertyConvertible {
	public func asProperty() -> STNProperty<STNBackdropEffect> {
		STNProperty(self)
	}
}

extension STNGPUDrawing: STNPropertyConvertible {
	public func asProperty() -> STNProperty<STNGPUDrawing> {
		STNProperty(self)
	}
}

extension STNDrawing: STNPropertyConvertible {
	public func asProperty() -> STNProperty<STNDrawing> {
		STNProperty(self)
	}
}

extension STNTextField.Options: STNPropertyConvertible {
	public func asProperty() -> STNProperty<STNTextField.Options> {
		STNProperty(self)
	}
}

extension STNWindow.Configuration: STNPropertyConvertible {
	public func asProperty() -> STNProperty<STNWindow.Configuration> {
		STNProperty(self)
	}
}

extension Array: STNPropertyConvertible {
	public func asProperty() -> STNProperty<Array<Element>> {
		STNProperty(self)
	}
}

extension STNSignal: STNPropertyConvertible {
	public func asProperty() -> STNProperty<Value> {
		STNProperty(self)
	}
}

extension STNComputed: STNPropertyConvertible {
	public func asProperty() -> STNProperty<Value> {
		STNProperty(self)
	}
}

extension STNSymbolAsset: STNPropertyConvertible {
	@MainActor public func asProperty() -> STNProperty<STNSymbolAsset> {
		STNProperty(self)
	}
}

extension STNSymbolPlayback: STNPropertyConvertible {
	@MainActor public func asProperty() -> STNProperty<STNSymbolPlayback> {
		STNProperty(self)
	}
}

extension Optional: STNPropertyConvertible where Wrapped == Double {
	@MainActor public func asProperty() -> STNProperty<Double?> {
		STNProperty(self)
	}
}
