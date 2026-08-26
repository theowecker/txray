# Changelog

## 0.1.0

- Static transaction analysis over explicit transactions, row and advisory locks, save callbacks, custom validations and migrations.
- Follows callbacks, concerns, service objects, `delegate` targets and `define_method` bodies across files.
- Tracks clients held in local variables, instance variables, constants and memoized readers.
- Text, json, sarif and github reporters, inline `# txray:disable` directives and configurable severities.
- Optional runtime guard with per-transaction attribution, an ignore API and a newline delimited JSON event log.
- `txray watch`, a live terminal monitor for transactions, durations and findings.
