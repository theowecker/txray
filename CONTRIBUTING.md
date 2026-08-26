# Contributing

```sh
bin/setup
bundle exec rake        # specs and rubocop
```

## Adding a rule

A rule is three things and a test.

1. `Rules.register` in `lib/txray/rule.rb`, with the severity, what the reader sees, and the fix.
2. A branch in `lib/txray/classifier.rb`, or a namespace in `lib/txray/catalog.rb` if the call is recognised by its receiver.
3. A scenario in `spec/txray/scenarios_spec.rb` that proves it fires, and one that proves it stays quiet on the shape it should ignore.

The second test matters more than the first. A rule that fires on correct code costs more than a rule that misses.

## Adding a transactional scope

`lib/txray/transaction_scope.rb` decides what counts as being inside a transaction. Anything added there needs a case showing that the corresponding commit-time callback is still left alone.

## Testing against other Rails versions

```sh
RAILS_VERSION=7.1 bundle install && RAILS_VERSION=7.1 bundle exec rspec
```

CI runs 7.1, 7.2 and 8.0 alongside Ruby 3.2, 3.3 and 3.4.

## Before opening a pull request

Run the scanner against a real application, not only the suite. False positives are the failure mode that matters, and they show up in real code long before they show up in fixtures.

## Releasing

Merging a version bump releases the gem. There is nothing to run by hand.

1. On a branch, bump `Txray::VERSION` in `lib/txray/version.rb` and add a `## x.y.z` section to `CHANGELOG.md`.
2. Open the pull request and merge it once CI is green.

On every push to `main` the release workflow reads `Txray::VERSION` and stops immediately if that version is already tagged, so ordinary merges do nothing. When the version is new it takes the release notes from the matching changelog section, runs the suite, tags the commit, publishes the gem to RubyGems through trusted publishing, and creates the GitHub release with the notes and the built gem attached.

The tag is created locally and only pushed once the gem is published, so a failure leaves nothing behind: fix it and merge again. A missing changelog section fails before the suite even runs. No API key is involved anywhere.
