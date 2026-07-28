#!/usr/bin/env bash
#
# run-tests.sh — runs the unit tests of a Gradle (Java) or npm (Angular)
# project, whichever is detected in the target directory, and normalizes
# the JUnit XML reports into ./test-results so GitHub Actions (or any
# JUnit-aware CI step) can consume them the same way for both apps.
#
# Usage: ./run-tests.sh [project_dir]   (defaults to this script's directory)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${1:-$SCRIPT_DIR}" && pwd)"
RESULTS_DIR="$PROJECT_DIR/test-results"

log()  { printf '[run-tests] %s\n' "$1"; }
fail() { printf '[run-tests] ERROR: %s\n' "$1" >&2; exit 1; }

log "Project directory: $PROJECT_DIR"

log "Cleaning previous test artifacts..."
rm -rf "$RESULTS_DIR"
mkdir -p "$RESULTS_DIR"

if [[ -f "$PROJECT_DIR/gradlew" && ( -f "$PROJECT_DIR/build.gradle" || -f "$PROJECT_DIR/build.gradle.kts" ) ]]; then
    PROJECT_TYPE="gradle"
elif [[ -f "$PROJECT_DIR/package.json" ]]; then
    PROJECT_TYPE="npm"
else
    fail "Unable to detect project type in $PROJECT_DIR (expected gradlew+build.gradle or package.json)"
fi

log "Detected project type: $PROJECT_TYPE"

cd "$PROJECT_DIR" || fail "Cannot cd into $PROJECT_DIR"

case "$PROJECT_TYPE" in

    gradle)
        command -v java >/dev/null 2>&1 || fail "java is required but was not found on PATH"
        log "java: $(java -version 2>&1 | head -n1)"

        [[ -x "./gradlew" ]] || chmod +x ./gradlew
        [[ -f "./gradle/wrapper/gradle-wrapper.jar" ]] || fail "gradle-wrapper.jar is missing (corrupt checkout?)"

        rm -rf "build/test-results"

        ./gradlew clean test
        TEST_EXIT_CODE=$?

        SOURCE_DIR="build/test-results/test"
        if [[ -d "$SOURCE_DIR" ]] && compgen -G "$SOURCE_DIR/*.xml" > /dev/null; then
            cp "$SOURCE_DIR"/*.xml "$RESULTS_DIR/"
        fi
        ;;

    npm)
        command -v npm >/dev/null 2>&1 || fail "npm is required but was not found on PATH"
        log "node: $(node -v), npm: $(npm -v)"

        if [[ ! -d "node_modules" ]]; then
            log "node_modules missing, installing dependencies with npm ci..."
            npm ci --prefer-offline || fail "npm ci failed"
        fi

        rm -rf "reports"

        npm test
        TEST_EXIT_CODE=$?

        SOURCE_DIR="reports"
        if [[ -d "$SOURCE_DIR" ]] && compgen -G "$SOURCE_DIR/*.xml" > /dev/null; then
            cp "$SOURCE_DIR"/*.xml "$RESULTS_DIR/"
        fi
        ;;
esac

if compgen -G "$RESULTS_DIR/*.xml" > /dev/null; then
    log "JUnit XML report(s) copied to $RESULTS_DIR"
else
    log "WARNING: no JUnit XML report found in $RESULTS_DIR"
fi

if [[ "$TEST_EXIT_CODE" -eq 0 ]]; then
    log "Tests passed."
else
    log "Tests failed (exit code $TEST_EXIT_CODE)."
fi

exit "$TEST_EXIT_CODE"
