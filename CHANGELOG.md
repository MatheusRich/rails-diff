## [Unreleased]

## [0.3.0] - 2025-02-23

- Allow passing options to generate the new application

```sh
rails-diff file Gemfile --new-app-options="--database=postgresql"
```

## [0.2.1] - 2025-02-22

- Add missing version command
- Consistent error messages
- Ensure rails path exists and dependencies are installed

## [0.2.0] - 2025-02-21

- Allow comparing a specific commit

```sh
rails-diff file Dockerfile --commit 3e7640
```

- Allow failing the command when there are diffs

```sh
rails-diff file Dockerfile --fail-on-diff
```

- Return no output when there's no diff

M## [0.1.1] - 2025-02-21

- Fix generator differ

## [0.1.0] - 2025-02-21

- Initial release

[0.3.0]: https://github.com/matheusrich/rails-diff/releases/tag/v0.3.0
[0.2.1]: https://github.com/matheusrich/rails-diff/releases/tag/v0.2.1
[0.2.0]: https://github.com/matheusrich/rails-diff/releases/tag/v0.2.0
[0.1.1]: https://github.com/matheusrich/rails-diff/releases/tag/v0.1.1
[0.1.0]: https://github.com/matheusrich/rails-diff/releases/tag/v0.1.0
