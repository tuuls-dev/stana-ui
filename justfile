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

# Run one named headless workload (or all); use --list to discover workloads.
benchmark *args:
    @Scripts/benchmark.sh "$@"

# Run one isolated engine layout workload in release mode.
benchmark-layout *args:
    @Scripts/benchmark-layout.sh "$@"

# Validate isolated deterministic layout fixtures without timing.
benchmark-layout-validate:
    swift run LayoutBenchmarks all --validate --sizes 1,8

# Check every benchmark workload without collecting timings.
benchmark-validate:
    @Scripts/benchmark.sh all --validate --sizes 1,8

# Run benchmark harness tests separately from timing.
benchmark-test:
    swift test --package-path Benchmarks -Xswiftc -warnings-as-errors

# Create an unsigned macOS app in dist/ from a consumer package.
package package-path product bundle-id:
    Scripts/package-macos-app.sh "$1" "$2" "$3"

# Run all non-GUI verification sequentially, stopping on the first failure.
check: check-format test check-api check-runtime build-examples build-release benchmark-test benchmark-layout-validate
