# 1️⃣ Basic parsing
uri = Addressable::URI.parse("http://example.com/path/to/resource/")

# Components – each call returns a plain Ruby object.
puts uri.scheme   # => "http"
puts uri.host     # => "example.com"
puts uri.path     # => "/path/to/resource/"
