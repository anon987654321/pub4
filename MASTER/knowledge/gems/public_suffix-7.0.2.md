# PublicSuffix forRuby

PublicSuffix parses domain names using the Public Suffix List.

## Links
- Homepage: https://simonecarletti.com/code/publicsuffix-ruby
- Repository: https://github.com/weppos/publicsuffix-ruby
- API Docs: https://rubydoc.info/gems/public_suffix
- Blog post: https://simonecarletti.com/blog/2010/06/public-suffix-list-library-for-ruby/

## Requirements
Ruby >= 3.2. Install via:
gem install public_suffix
or add `gem 'public_suffix'` to your Gemfile.

## Usage
Extract the registrable domain:
domain = PublicSuffix.domain("www.google.co.uk")
domain.tld      # => "uk"
domain.sld      # => "google"
domain.domain   # => "co.uk"
domain.subdomain # => "www"

Validate:
PublicSuffix.valid?("example.com")      # => true
PublicSuffix.valid?("blogspot.com")     # => false

Strict validation without default rule:
PublicSuffix.valid?("example.tldnotlisted", default_rule: nil) # => false

## Fully Qualified Domain Names
The library treats names ending with a dot as Fully Qualified Domain Names (FQDN):
PublicSuffix.domain("www.google.com.") # => "google.com"

## Private Domains
By default the library includes private domains:
PublicSuffix.domain("something.blogspot.com") # => "something.blogspot.com"

Exclude private domains:
PublicSuffix.domain("something.blogspot.com", ignore_private: true) # => "blogspot.com"

Disable private domain support:
PublicSuffix::List.default = PublicSuffix::List.parse(
  PublicSuffix::List::DEFAULT_LIST_PATH, private_domains: false
)
PublicSuffix.domain("something.blogspot.com") # => "blogspot.com"

## Adding Custom Domains
Add a domain manually:
PublicSuffix::List.default << PublicSuffix::Rule.factory('onmicrosoft.com')

## Public Suffix List
A public suffix is a domain suffix under which users can directly register names.
Examples: ".com", ".co.uk", "pvt.k12.wy.us". The list is community‑maintained.

## Why Use the Public Suffix List?
Algorithms cannot reliably determine registration limits for each top‑level domain.
The list provides an accurate registry of suffixes, preventing security issues such ascookies being set on broader scopes than intended.

## Network Requests
PublicSuffix does not perform network requests. It ships with a bundled list.

## Terminology
- **TLD**: Top‑Level Domain (e.g., ".org").
- **SLD**: Second‑Level Domain (e.g., "mozilla" in "mozilla.org").
- **TRD**: Third‑Level Domain (e.g., "www" in "www.mozilla.org").
- **FQDN**: Fully Qualified Domain Name, terminated by a dot.

## Documentation and Support
- Docs: https://rubydoc.info/gems/public_suffix
- Issue tracker: https://github.com/weppos/publicsuffix-ruby/issues- Contribute: fork, branch, test, submit a pull request.

## Security
See SECURITY.md for vulnerability reporting details.

## Changelog
View changes in CHANGELOG.md.

## License
MIT © Simone Carletti. The Public Suffix List is MPL‑2.0.