# txray

Static analysis that finds slow work hidden inside database transactions.

A transaction holds a connection and every row lock it has taken until it commits. Anything slow that happens in between (an HTTP request, a Stripe call, an SMTP delivery, a subprocess, a loop over a collection) extends that hold, and every writer queued behind those locks waits with it. The worst cases are the ones nobody wrote on purpose: an `after_create` callback three method calls away from a payment API.

txray parses your application with [Prism](https://github.com/ruby/prism) and follows callbacks, concerns and helper methods to find that work. It never boots your app and never runs your code, so it reports problems on paths your test suite has never executed.

```
app/models/order.rb
  13:5  high   external-service-in-transaction
    External service call `Stripe::PaymentIntent.create(amount: total_cents)` runs inside the `after_create :settle` callback
      via Order#charge_card (app/models/order.rb:12)
    Third party clients hold the connection and the row locks for their full round trip. Call them after commit.
```

## Install

```ruby
group :development, :test do
  gem "txray", require: false
end
```

Then run it:

```sh
bundle exec txray
```

It exits non zero when it finds something, so it drops straight into CI.

## What counts as a transaction

txray does not only look for `transaction do`. It treats all of these as transactional scope:

| Scope | Example |
| --- | --- |
| Explicit blocks | `Order.transaction { ... }`, `ActiveRecord::Base.transaction { ... }` |
| Row locks | `order.with_lock { ... }`, any method that calls `lock!` |
| Callbacks that run inside the save transaction | `before_save`, `after_create`, `around_update`, `after_destroy`, `after_touch` and friends |

`after_commit`, `after_create_commit`, `after_rollback` and the rest of the commit callbacks run outside the transaction, so txray deliberately leaves them alone. That distinction is the whole point: moving a call from `after_create` to `after_commit` is usually the fix.

## What it looks for

| Rule | Severity |
| --- | --- |
| `http-in-transaction` | high |
| `external-service-in-transaction` | high |
| `mail-in-transaction` | high |
| `shell-in-transaction` | high |
| `sleep-in-transaction` | high |
| `job-enqueue-in-transaction` | medium |
| `upload-in-transaction` | medium |
| `iteration-in-transaction` | medium |
| `cache-in-transaction` | low |

`bundle exec txray --rules` prints the full list with the suggested fix for each.

## Following the call

The interesting offenders are rarely in the transaction block itself. Given this:

```ruby
class Order < ApplicationRecord
  include Notifiable

  after_create :settle

  def settle
    charge_card
    notify_downstream
  end

  def charge_card
    Stripe::PaymentIntent.create(amount: total_cents)
  end
end
```

txray resolves `after_create :settle` to `Order#settle`, follows `charge_card` into the same class and `notify_downstream` into the `Notifiable` concern in another file, and reports both calls with the path it took to reach them.

It follows four kinds of call: bare calls in the same class, `self.` calls into class methods, `Constant.method` calls into another class, and `Constant.new(...).method` into a service object. So a transaction that only says `Checkout.new(order).call` is still traced to the Stripe call three files away. `--depth` controls how far it follows (three levels by default).

## Configuration

```sh
bundle exec txray --init
```

```yaml
include:
  - app
  - lib
exclude:
  - spec
  - test
  - vendor
max_depth: 3
fail_level: low
disabled_rules:
  - cache-in-transaction
external_clients:
  - InternalApi
  - LegacySoapClient
runtime:
  enabled: false
  threshold_ms: 250
  on_violation: log
```

`external_clients` teaches txray about your own service wrappers. Any constant under those namespaces is treated like a third party client.

## Command line

```
Usage: txray [options] [paths]
    -f, --format FORMAT   text, json, sarif or github (default: text)
    -c, --config PATH     path to a .txray.yml file
        --fail-level      low, medium, high or none (default: low)
        --only RULES      report only these rule ids
        --except RULES    skip these rule ids
        --depth N         how far to follow method calls (default: 3)
        --rules           list every rule and exit
        --init            write a default .txray.yml
```

## CI

```yaml
- name: Scan for slow transactions
  run: bundle exec txray --format github
```

`--format github` writes inline annotations on the pull request. `--format sarif` uploads to GitHub code scanning:

```yaml
- run: bundle exec txray --format sarif > txray.sarif || true
- uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: txray.sarif
```

## Runtime guard

Static analysis cannot see through metaprogramming or a gem's internals. The optional runtime guard catches what is left, from inside a running application:

```yaml
runtime:
  enabled: true
  threshold_ms: 250
  on_violation: raise
```

It reports a transaction that stays open past the threshold, a job enqueued while a transaction is open, mail delivered while a transaction is open, and any `Net::HTTP` request made while a transaction is open (which covers Faraday, HTTParty, RestClient, Octokit and everything else built on it). `on_violation: log` warns, `raise` fails loudly. Run it as `raise` in test and `log` in development.

## How this differs from what already exists

[isolator](https://github.com/palkan/isolator) detects the same class of problem at runtime, so it only sees code your tests actually execute. txray answers the same question statically: no boot, no database, no coverage requirement, and it works on a cold checkout of a codebase you have never run. The two compose well. Nothing in `rubocop-rails` covers this.

## Roadmap

The rule registry is keyed by category so the transaction rules are the first family rather than the only one. Planned: query rules (N+1 shapes in views and loops, `count` where `size` would do, unbounded `all` loads, missing `includes`), schema rules (unindexed foreign keys and filtered columns), and job rules (Active Record objects passed as job arguments).

## Development

```sh
bin/setup
bundle exec rake
```

## License

MIT
