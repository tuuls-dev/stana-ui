set shell := ["sh", "-eu", "-c"]
set positional-arguments

# List available developer commands.
default:
    @just --list

# Format repository Swift and Objective-C sources.
format:
    Scripts/format-swift.sh
    Scripts/format-objc.sh

# Check Swift and Objective-C formatting without changing files.
check-format:
    Scripts/format-swift.sh lint
    Scripts/format-objc.sh lint

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

# Confirm, bump VERSION, commit, and push a major, minor, or patch release tag.
version bump:
    @Scripts/version.sh "$1"

# Build all consumer examples with Swift warnings as errors.
build-examples:
    for example in Counter Preferences EditableCollection WindowConfiguration TextFields HybridRendering; do \
        swift build --package-path "Examples/$example" -Xswiftc -warnings-as-errors; \
    done

# Run a consumer example.
example example="Counter":
    @example="${1#example=}"; \
        case "$example" in \
            Counter|Preferences|EditableCollection|WindowConfiguration|TextFields|HybridRendering) ;; \
            *) printf 'Unknown example: %s\nUsage: just example [Counter|Preferences|EditableCollection|WindowConfiguration|TextFields|HybridRendering]\n' "$example" >&2; exit 1 ;; \
        esac; \
        swift run --package-path "Examples/$example"

# Run the headless benchmark in release mode and print its JSON report.
benchmark:
    swift run --package-path Benchmarks -c release

# Run the native hybrid workload (120 warm-up + 1,000 completed offscreen frames).
benchmark-native mode="persistent" output="/tmp/stana-native-benchmark.json":
    @sh Scripts/benchmark-native.sh "$1" "$2"

# Create an unsigned macOS app in dist/ from a consumer package.
package package-path product bundle-id:
    Scripts/package-macos-app.sh "$1" "$2" "$3"

# Run all non-GUI verification sequentially, stopping on the first failure.
check: check-format check-boundaries test check-api check-runtime build-examples build-release
