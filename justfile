set shell := ["sh", "-eu", "-c"]
set positional-arguments

# List available developer commands.
default:
    @just --list

# Format all repository Swift files with the bundled Swift formatter.
format:
    Scripts/format-swift.sh

# Check Swift formatting without changing files.
check-format:
    Scripts/format-swift.sh lint

# Build the library in debug mode.
build:
    swift build

# Build the library in release mode with Swift warnings as errors.
build-release:
    swift build -c release -Xswiftc -warnings-as-errors

# Run tests with Swift and native warnings as errors.
test:
    swift test -Xswiftc -warnings-as-errors -Xcc -Werror

# Run native GUI tests (requires a logged-in macOS window server).
test-gui:
    STANA_GUI_TESTS=1 swift test -Xswiftc -warnings-as-errors -Xcc -Werror

# Check dependency and native-platform boundaries.
check-boundaries:
    Scripts/check-boundaries.sh

# Check valid and invalid public API fixtures.
check-api:
    Scripts/check-api-fixtures.sh

# Check runtime faults in isolated processes.
check-runtime:
    Scripts/check-runtime-faults.sh

# Build all four consumer examples with Swift warnings as errors.
build-examples:
    for example in Counter Preferences EditableCollection WindowConfiguration; do \
        swift build --package-path "Examples/$example" -Xswiftc -warnings-as-errors; \
    done

# Run an example: Counter, Preferences, EditableCollection, or WindowConfiguration.
example example="Counter":
    @example="${1#example=}"; \
        case "$example" in \
            Counter|Preferences|EditableCollection|WindowConfiguration) ;; \
            *) printf 'Unknown example: %s\nUsage: just example [Counter|Preferences|EditableCollection|WindowConfiguration]\n' "$example" >&2; exit 1 ;; \
        esac; \
        swift run --package-path "Examples/$example"

# Run the headless benchmark in release mode and print its JSON report.
benchmark:
    swift run --package-path Benchmarks -c release

# Create an unsigned macOS app in dist/ from a consumer package.
package package-path product bundle-id:
    Scripts/package-macos-app.sh "$1" "$2" "$3"

# Run all non-GUI verification sequentially, stopping on the first failure.
check: check-format check-boundaries test check-api check-runtime build-examples build-release
