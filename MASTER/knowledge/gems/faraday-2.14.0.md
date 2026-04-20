# Faraday

[![Gem Version](https://badge.fury.io/rb/faraday.svg)](https://rubygems.org/gems/faraday)  
[![GitHub Actions CI](https://github.com/lostisland/faraday/actions/workflows/CI/badge.svg)](https://github.com/lostisland/faraday/actions?query=workflow%3ACI)  
[![GitHub Discussions](https://img.shields.io/github/discussions/lostisland/faraday?logo=github)](https://github.com/lostisland/faraday/discussions)

Faraday is an HTTP client library that provides a unified interface for multiple adapters (e.g., Net::HTTP) and uses Rack middleware to process request/response cycles.

## Why use Faraday?

- Supports multiple adapters (Net::HTTP, Typhoeus, Patron, Excon, HTTPClient, etc.)  
- Enables Rack middleware for request/response manipulation  
- Offers persistent connections (keep‑alive)  
- Provides parallel request execution  
- Parses responses automatically (JSON, XML, YAML)  
- Streams responses and supports file uploads  
- Facilitates building sophisticated API clients

## Supported Ruby versions

The library supports and tests against officially supported Ruby implementations. Currently, Ruby 3.0+ is supported. If a feature fails on a supported version, it is a bug. The library may function on other versions but will not receive official support.

## Contributing

To contribute, view issues marked `help wanted`. Before coding, read the [Contributing Guide][contributing].

## Copyright

© 2009‑2023, the Faraday Team. Website and branding design by [Elena Lo Piccolo](https://elelopic.design).