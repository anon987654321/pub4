# OpenSSL for Ruby

OpenSSL for Ruby provides SSL/TLS and general-purpose cryptography via the OpenSSL library.

OpenSSL for Ruby is also known as openssl (lowercase) or Ruby/OpenSSL for clarity.

## Compatibility and maintenance policy

OpenSSL for Ruby is a default gem. Each stable branch remains supported while it is included in a supported Ruby version.

| Version | Minimum Ruby | OpenSSL compatibility               | Bundled with | Maintenance |
|---------|--------------|--------------------------------------|--------------|-------------|
| 4.0.x   | Ruby 2.7     | OpenSSL 1.1.1-3.x, LibreSSL 3.9+, AWS-LC | Ruby 4.0     | Bug fixes   |
| 3.3.x   | Ruby 2.7     | OpenSSL 1.0.2-3.x, LibreSSL 3.1+     | Ruby 3.4     | Bug fixes   |
| 3.2.x   | Ruby 2.7     | OpenSSL 1.0.2-3.x, LibreSSL 3.1+     | Ruby 3.3     | Bug fixes   |
| 3.1.x   | Ruby 2.6     | OpenSSL 1.0.2-3.x, LibreSSL 3.1+     | Ruby 3.2     | Security only |
| 3.0.x   | Ruby 2.6     | OpenSSL 1.0.2-3.x, LibreSSL 3.1+     | Ruby 3.1     | End-of-life |
| 2.2.x   | Ruby 2.3     | OpenSSL 0.9.8-1.1.1, LibreSSL 2.9+   | Ruby 3.0     | End-of-life |
| 2.1.x   | Ruby 2.3     | OpenSSL 0.9.8-1.1.1, LibreSSL 2.5+   | Ruby 2.5-2.7 | End-of-life |
| 2.0.x   | Ruby 2.3     | OpenSSL 0.9.8-1.1.1, LibreSSL 2.3+   | Ruby 2.4     | End-of-life |

[default gem]: https://docs.ruby-lang.org/en/master/standard_library_md.html
[Ruby Maintenance Branches]: https://www.ruby-lang.org/en/downloads/branches/

## Installation

Upgrade the openssl gem with RubyGems:

gem install openssl

If needed, specify the OpenSSL directory:

gem install openssl -- --with-openssl-dir=/opt/openssl

Alternatively, install with Bundler:

# Gemfile
gem 'openssl'

After running bundle install, the gem is available in your bundle.

[RubyGems.org openssl]: https://rubygems.org/gems/openssl

## Usage

Require openssl in your application:

require "openssl"

## Documentation

See https://ruby.github.io/openssl/.

## Contributing

Read CONTRIBUTING.md for contribution guidelines.

## Security

Report security issues to ruby-core following the process at Security.

[Security]: https://www.ruby-lang.org/en/security/