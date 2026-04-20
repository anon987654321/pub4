# Bundler

Bundler ensures that a Ruby application runs the same code on every machine.

Bundler manages the gems an application depends on. Given a list of gems, Bundler downloads and installs them, along with any dependencies. Before installation, it verifies version compatibility to guarantee that all gems load together. After installation, Bundler helps update selected gems when new versions appear, and records the exact versions installed so others can reproduce the environment.

## InstallationInstall or update to the latest version:

gem install bundler

Install a prerelease version (if available):

gem install bundler --pre

Uninstall Bundler:

gem uninstall bundler

## Usage

Initialize a Gemfile:

bundle initAdd a gem:

bundle add rspec

Install dependencies:

bundle install

Run an executable:

bundle exec rspec

## Troubleshooting

For common issues, see [TROUBLESHOOTING](TROUBLESHOOTING.md).

If problems persist, file an issue at https://github.com/ruby/rubygems/issues/new?labels=Bundler&template=bundler-related-issue.md.

## Changelog

View recent changes in [CHANGELOG](CHANGELOG.md).

## Community

Contact the Bundler core team and community via the [Bundler Slack](https://join.slack.com/t/bundler/shared_invite/zt-1rrsuuv3m-OmXKWQf8K6iSla4~F1DBjQ).

## Contributing

To contribute, read the [Contributor Guide](https://github.com/ruby/rubygems/blob/master/doc/bundler/contributing/README.md).

For substantial changes, follow the [RFC process](https://github.com/rubygems/rfcs).

## Support

Ruby Central maintains RubyGems and Bundler. Support Ruby Central by attending or sponsoring conferences such as RubyConf and RailsConf, or by becoming a supporting member at https://rubycentral.org/#/portal/signup.

## Code of Conduct

Adhere to the [Code of Conduct](https://github.com/ruby/rubygems/blob/master/CODE_OF_CONDUCT.md).

## License

Bundler is released under the MIT License (see [LICENSE](LICENSE.md)).