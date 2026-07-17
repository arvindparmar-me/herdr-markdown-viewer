#!/usr/bin/env bash
# Minimal assertion helpers, sourced by test files.
failures=0
tests_run=0

assert_eq() {
  # $1 expected, $2 actual, $3 message
  tests_run=$((tests_run + 1))
  if [[ "$1" == "$2" ]]; then
    printf 'ok %d - %s\n' "$tests_run" "$3"
  else
    printf 'not ok %d - %s\n' "$tests_run" "$3" >&2
    printf '  expected: %s\n  actual:   %s\n' "$1" "$2" >&2
    failures=$((failures + 1))
  fi
}

assert_contains() {
  # $1 haystack, $2 needle, $3 message
  tests_run=$((tests_run + 1))
  case "$1" in
    *"$2"*) printf 'ok %d - %s\n' "$tests_run" "$3" ;;
    *)
      printf 'not ok %d - %s\n' "$tests_run" "$3" >&2
      printf '  expected to contain: %s\n  in: %s\n' "$2" "$1" >&2
      failures=$((failures + 1))
      ;;
  esac
}

finish_tests() {
  if [[ "$failures" -gt 0 ]]; then
    printf '%d of %d tests failed\n' "$failures" "$tests_run" >&2
    exit 1
  fi
  printf '%d tests passed\n' "$tests_run"
}
