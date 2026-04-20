# [![Faraday](./docs/_media/home-logo.svg)][website]

[![Gem Version](https://badge.fury.io/rb/faraday.svg)](https://rubygems.org/gems/faraday)
[![GitHub Actions CI](https://github.com/lostisland/faraday/actions/workflows/CI/badge.svg)](https://github.com/lostisland/faraday/actions?query=workflow%3ACI)
[![GitHub Discussions](https://img.shields.io/github/discussions/lostisland/faraday?logo=github)](https://github.com/lostisland/faraday/discussions)

Faraday is an HTTP client library that abstracts multiple adapters (Net::HTTP, Typhoeus, Excon, HTTPClient, etc.) and uses Rack middleware to process requests and responses.

See [Awesome Faraday][] for adapter information.

## Why use Faraday?
Use Faraday to build API clients or web service libraries that abstract HTTP details.

## Supported Ruby versions
We support officially supported Ruby versions. See [actions][] for test status. Although the library may work on other versions, support is limited to the versions listed above.

To add support for another version, volunteer as maintainer; you must ensure all tests pass and promptly provide patches for failures. Critical issues at a major release may lead to dropping support for that version.

## Contribute
Check issues for `help wanted` label before coding. Read the [Contributing Guide][contributing] first.

## Copyright

© 2009 - 2023, the Faraday Team. Website and branding design by [Elena Lo Piccolo](https://elelopic.design)

[awesome]: https://github.com/lostisland/awesome-faraday/#adapters
[website]: https://lostisland.github.io/faraday
[contributing]: https://github.com/lostisland/faraday/blob/main/.github/CONTRIBUTING.md
[actions]: https://github.com/lostisland/faraday/actions