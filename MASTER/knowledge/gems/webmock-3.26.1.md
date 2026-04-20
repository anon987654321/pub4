WebMock
=======
[![Gem Version](https://badge.fury.io/rb/webmock.svg)](http://badge.fury.io/rb/webmock)
[![Build Status](https://github.com/bblimke/webmock/actions/workflows/CI.yml/badge.svg?branch=master)](https://github.com/bblimke/webmock/actions)
[![Code Climate](https://codeclimate.com/github/bblimke/webmock/badges/gpa.svg)](https://github.com/bblimke/webmock)
[![Awesome Ruby](https://awesome.re/mentioned-badge.svg)](https://github.com/markets/awesome-ruby)

Library for stubbing and configuring HTTP requests in Ruby.

Features
--------
- Stub low‑level HTTP calls without changing test code when the HTTP library changes.
- Set and verify expectations on requests by method, URI, headers, and body.
- Match URIs and headers in different encodings.
- Support Test::Unit, RSpec, MiniTest.
- Compatible with Async::HTTP::Client, Curb, EM‑HTTP‑Request, Excon, HTTPClient, httpx, Manticore, Net::HTTP, HTTParty, REST Client, Patron, Typhoeus.

Supported Ruby versions-----------------------
MRI 2.6–3.4, JRuby.

Installation
------------gem install webmock
# or in Gemfile
group :test { gem "webmock" }

Development
-----------
git clone https://github.com/bblimke/webmock.git
cd webmock
rake install

Upgrade from v1.x to v2.x
-------------------------
See CHANGELOG.md.

Integration with test frameworks
--------------------------------
# Test::Unit
require "webmock/test_unit"

# MiniTest
require "webmock/minitest"

# RSpec
require "webmock/rspec"

# Outside test frameworks
require "webmock"
include WebMock::API
WebMock.enable!

Examples
--------
Stubs
-----
stub_request(:any, "www.example.com")
Net::HTTP.get("www.example.com", "/") # => Success

stub_request(:post, "www.example.com").
  with(body: "abc", headers: {"Content-Length" => 3})
uri = URI.parse("http://www.example.com/")
req = Net::HTTP::Post.new(uri.path)
req["Content-Length"] = 3
res = Net::HTTP.start(uri.host, uri.port) { |http| http.request(req, "abc") }
res # => Success

Matching body and headers with regexes
--------------------------------------
stub_request(:post, "www.example.com").
  with(body: /world$/, headers: {"Content-Type" => /image\/.+/}).
  to_return(body: "abc")

uri = URI.parse("http://www.example.com/")
req = Net::HTTP::Post.new(uri.path)
req["Content-Type"] = "image/png"
res = Net::HTTP.start(uri.host, uri.port) { |http| http.request(req, "hello world") }
res # => Success

# Matching body against a hash
stub_request(:post, "www.example.com").
  with(body: {data: {a: "1", b: "five"}})
RestClient.post("www.example.com", "data[a]=1&data[b]=five",
  content_type: "application/x-www-form-urlencoded") # => Success

# Matching custom headers
stub_request(:any, "www.example.com").
  with(headers: {"Header-Name" => "Header-Value"})
req = Net::HTTP::Post.new("/")
req["Header-Name"] = "Header-Value"
res = Net::HTTP.start("www.example.com") { |http| http.request(req, "abc") }
res # => Success

# Matching multiple headers with same name
stub_request(:get, "www.example.com").
  with(headers: {"Accept" => ["image/jpeg", "image/png"]})
req = Net::HTTP::Get.new("/")
req["Accept"] = ["image/png"]
req.add_field("Accept", "image/jpeg")
Net::HTTP.start("www.example.com") { |http| http.request(req) } # => Success

# Matching blockstub_request(:post, "www.example.com") { |request| request.body == "abc" }
RestClient.post("www.example.com", "abc") # => Success

Basic authentication------------------
stub_request(:get, "www.example.com").with(basic_auth: ["user", "pass"])
Net::HTTP.start("www.example.com") do |http|
  req = Net::HTTP::Get.new("/")
  req.basic_auth "user", "pass"
  http.request(req)
end # => Success

# Since v2.0.0 credentials in Authorization header are not matched.
# Use URL userinfo for matching.

Matching URIs
-------------
WebMock normalizes URIs; it matches all equivalent forms:
"www.example.com", "www.example.com/", "www.example.com:80", …
Including userinfo representations:
"a b:pass@www.example.com", "a%20b:pass@www.example.com:80/"

Regular expressions and lambda matchers are also supported.

RFC 6570 URI templates
----------------------
uri_template = Addressable::Template.new "www.example.com/{id}/"
stub_request(:any, uri_template)
Net::HTTP.get("www.example.com", "/webmock/") # => Success

Query parameters
----------------
stub_request(:get, "www.example.com").with(query: {"a" => ["b", "c"]})
RestClient.get("http://www.example.com/?a[]=b&a[]=c") # => Success

Partial query parameter matching
------------------------------
stub_request(:get, "www.example.com").
  with(query: hash_including({"a" => ["b", "c"]}))
RestClient.get("http://www.example.com/?a[]=b&a[]=c&x=1") # => Success

Response definitions
--------------------
stub_request(:any, "www.example.com").
  to_return(body: "abc", status: 200, headers: {"Content-Length" => 3})
Net::HTTP.get("www.example.com", "/") # => "abc"

Set Content-Type for JSON parsing:
stub_request(:any, "www.example.com").
  to_return(headers: {"content_type" => "application/json"}, body: "{}")

IO and file responses
----------------------
File.open("/tmp/response.txt", "w") { |f| f.puts "abc" }
stub_request(:any, "www.example.com").
  to_return(body: File.new("/tmp/response.txt"), status: 200)
Net::HTTP.get("www.example.com", "/") # => "abc\n"

JSON responses
--------------
stub_request(:any, "www.example.com").
  to_return_json(body: {foo: "bar"})
Net::HTTP.get("www.example.com", "/") # => "{\"foo\":\"bar\"}"

Custom status messages
----------------------
stub_request(:any, "www.example.com").
  to_return(status: [500, "Internal Server Error"])
Net::HTTP.start("www.example.com") { |http|
  Net::HTTP.get("/").message # => "Internal Server Error"
}

Dynamic responses
-----------------
stub_request(:any, "www.example.net").
  to_return { |request| {body: request.body} }
RestClient.post("www.example.net", "abc") # => "abc\n"

Block or lambda responses
-------------------------
stub_request(:any, "www.example.net").
  to_return(lambda { |request| {body: request.body} })
RestClient.post("www.example.net", "abc") # => "abc\n"

Rack responses
--------------
class MyRackApp  def self.call(env) [200, {}, ["Hello"]] end
endstub_request(:get, "www.example.com").to_rack(MyRackApp)
RestClient.post("www.example.com") # => "Hello"

Error responses
---------------
stub_request(:any, "www.example.net").to_raise(StandardError)
RestClient.post("www.example.net", "abc") # => StandardError

Timeout errors
--------------
stub_request(:any, "www.example.net").to_timeoutRestClient.post("www.example.net", "abc") # => RestClient::RequestTimeout

Multiple responses
------------------
stub_request(:get, "www.example.com").
  to_return({body: "abc"}, {body: "def"})
Net::HTTP.get("www.example.com", "/") # => "abc\n"
Net::HTTP.get("www.example.com", "/") # => "def\n"
# Subsequent calls return the last response.

Times limit
-----------
stub_request(:get, "www.example.com").
  to_return({body: "abc"}).times(2).then.
  to_return({body: "def"})
Net::HTTP.get("www.example.com", "/") # => "abc\n"
Net::HTTP.get("www.example.com", "/") # => "abc\n"
Net::HTTP.get("www.example.com", "/") # => "def\n"

Removing unused stubs----------------------
stub = stub_request(:get, "www.example.com")
remove_request_stub(stub)

Network access
--------------
WebMock.allow_net_connect!
Net::HTTP.get("www.example.com", "/") # => Success
assert_requested :get, "http://www.example.com"

WebMock.disable_net_connect!
Net::HTTP.get("www.example.com", "/") # => Failure

Allow localhost:
WebMock.disable_net_connect!(allow_localhost: true)

Allow specific hosts/ports
-------------------------
WebMock.disable_net_connect!(allow: "www.example.org")
WebMock.disable_net_connect!(allow: "www.example.org:8080")
WebMock.disable_net_connect!(allow: %r{ample\.org/foo})
allow = lambda { |uri| uri.host.length.even? }
WebMock.disable_net_connect!(allow: allow)

Connecting via Net::HTTP.start
------------------------------
WebMock delays connection until a request is invoked. Use
:net_http_connect_on_start to force immediate connection:
WebMock.allow_net_connect!(net_http_connect_on_start: "www.example.com")

Resetting state
--------------
WebMock.reset!                    # clears all stubs and historyWebMock.reset_executed_requests!  # clears only request counters

Selective enable/disable
------------------------
WebMock.disable!                    # all adapters
WebMock.disable!(except: [:net_http])
WebMock.enable!(except: [:patron])  # all except PatronMatch precedence
----------------
Last declared stub wins.

Header matching
---------------
1. Stubbed headers are identical to request headers.
2. Stubbed headers are a subset of request headers.
3. No stubbed headers are specified.

Header normalization treats case and format variations as equal.

Recording and replaying
----------------------
Use VCR together with WebMock to record real HTTP interactions.

Callbacks
---------
WebMock.after_request do |signature, response|
  puts "Request #{signature} returned #{response}"
end

Callbacks for real requests only (except Patron):
WebMock.after_request(except: [:patron], real_requests_only: true) { |sig, resp| … }

Bugs and support
----------------
Report issues at https://github.com/bblimke/webmock/issues.

Triage
------
Subscribe on CodeTriage to help maintainers.

Suggestions
-----------
Email webmock-users@googlegroups.com.

Development
-----------
Fork, work on a branch, rebase against master before pulling.

Credits
-------
Inspired by FakeWeb. Contributors listed at https://github.com/bblimke/webmock/graphs/contributors.

Copyright
---------
© 2009‑2010 Bartosz Blimke. See LICENSE for details.