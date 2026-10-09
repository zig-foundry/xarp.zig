# Changelog

All notable changes to `xarp.zig` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial Zig port of the Rust `xarp` crate, targeting Zig 0.16.
- Color system: `Color`, `Rgb`, and `Effects` supporting named, 256-color, and true RGB palettes.
- Styling primitives: `Style`, `Styles`, and preset constants (`RED`, `BOLD`, etc.).
- Core parser engine: `Xarp`, `Arg`, `ArgMatches`, and `Outcome`.
- Parsing functions: `tryGetMatchesFrom` and `tryGetMatchesWithEnv` (allows passing custom environment maps for isolated testing).
- Standard CLI entry point: `getMatches` prints help or version info and exits (exit code 0 for help/version, code 2 for parsing errors).
- Value extraction utilities: `tryGetOne`, `getOneParsed`, `getManyParsed`, and `valueError`.
- Formatted output helpers: `printHelp` and `printVersion`.
- Libc integration: linked via `build.zig` to support `getenv` for `NO_COLOR` and argument environment fallbacks.

### Zig-Specific Notes

Because Zig does not support custom operator overloading or string-carrying `Result` types like Rust:

- Replaced bitwise `|` with explicit helper methods: `merge`, `withColor`, and `bitOr`.
- Introduced `Outcome` in place of `Result<ArgMatches, XarpError>`.
- Pass command-line arguments via `init.minimal.args.toSlice` (Zig 0.16 has no global args array).
- Remember to call `deinit` on `Xarp`, `Outcome`, and any rendered help or version strings to avoid memory leaks.
