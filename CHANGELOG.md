# Changelog

## 0.2.0

- Track clients held in local variables, instance variables, constants, memoized readers and `delegate` targets, so the request is reported rather than the harmless construction.
- Resolve `send` and `public_send` with a symbol literal, `define_method` bodies and concern `included` blocks; report genuinely dynamic dispatch as a visible low severity blind spot.
- Cover custom validations, `before_commit`, advisory locks and migration bodies as transactional scope, and add rules for broadcasts and blocking file, CSV and image work.
- RuboCop style directive regions: `# txray:disable RULE` ... `# txray:enable RULE`, `all`, and whole file suppression.
- Rebuilt live monitor with stacked meters, a latency histogram and severity colour, clamped to the terminal; `rails generate txray:install`; `NO_COLOR` support.
- Report paths relative to the working directory, and escape GitHub workflow commands correctly, so annotations and SARIF attach to the right file.
- `--format github` now writes a job summary table in addition to inline annotations.
- Runtime guard supports Rails 7.0 through 8.x, timing the transaction directly on versions that do not emit `start_transaction.active_record`.
- Clear errors for a malformed config, a missing path and an unparseable file, all of which previously reported a clean scan that never happened.

## 0.1.0

- Static transaction analysis over explicit transactions, row and advisory locks, save callbacks, custom validations and migrations.
- Follows callbacks, concerns, service objects, `delegate` targets and `define_method` bodies across files.
- Tracks clients held in local variables, instance variables, constants and memoized readers.
- Text, json, sarif and github reporters, inline `# txray:disable` directives and configurable severities.
- Optional runtime guard with per-transaction attribution, an ignore API and a newline delimited JSON event log.
- `txray watch`, a live terminal monitor for transactions, durations and findings.
