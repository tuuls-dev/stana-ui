set shell := ["sh", "-eu", "-c"]
set positional-arguments

# List available developer commands.
default:
    @just --list

# Format repository Swift sources.
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

# Run tests with Swift warnings as errors.
test:
    swift test -Xswiftc -warnings-as-errors

# Run native GUI tests (requires a logged-in macOS window server).
test-gui:
    swift build --product NativeInputProbe -Xswiftc -warnings-as-errors
    STANA_GUI_TESTS=1 swift test -Xswiftc -warnings-as-errors

# Check valid and invalid public API fixtures.
check-api:
    Scripts/check-api-fixtures.sh

# Check runtime faults in isolated processes.
check-runtime:
    Scripts/check-runtime-faults.sh

# Confirm, bump VERSION, commit, and push a major, minor, or patch release tag.
version bump:
    @Scripts/version.sh "$1"

# Build the Calculator example with Swift warnings as errors.
build-examples:
    swift build --package-path Examples/Calculator -Xswiftc -warnings-as-errors

# Run the Calculator example.
example:
    swift run --package-path Examples/Calculator

# Run the headless benchmark in release mode and print its JSON report.
benchmark:
    swift run --package-path Benchmarks -c release StanaBenchmarks

# Run the packaged native rendering benchmark (keep its window visible).
benchmark-native mode="persistent" output="/tmp/stana-native-benchmark.json":
    @sh Scripts/benchmark-native.sh "$1" "$2"

# Create an unsigned macOS app in dist/ from a consumer package.
package package-path product bundle-id:
    Scripts/package-macos-app.sh "$1" "$2" "$3"

# Run all non-GUI verification sequentially, stopping on the first failure.
check: check-format test check-api check-runtime build-examples build-release
