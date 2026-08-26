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

Releases are published by GitHub Actions through RubyGems trusted publishing, so no API key is needed and none is stored anywhere.

`main` requires a pull request, so the version bump goes through one and only the tag is pushed directly.

1. On a branch, bump `Txray::VERSION` in `lib/txray/version.rb` and add a `## x.y.z` section to `CHANGELOG.md`. The release notes are taken from that section verbatim, so a missing one fails the build.
2. Open the pull request and merge it once CI is green.
3. Tag the merged commit:

   ```sh
   git checkout main
   git pull
   git tag -a vx.y.z -m "txray x.y.z"
   git push origin vx.y.z
   ```

Pushing the tag is what triggers the release. The workflow checks the tag against `Txray::VERSION`, runs the suite, publishes the gem, and creates the GitHub release with the notes and the built gem attached. Nothing is published if any step fails, so a tag that does not match the version constant costs nothing but a deleted tag.
