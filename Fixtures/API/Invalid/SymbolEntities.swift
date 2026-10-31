import Stana

@MakeSTNSymbol
struct Invalid {
	static let svg = "<!DOCTYPE svg [<!ENTITY x 'bad'>]><svg viewBox='0 0 1 1'/>"
}
