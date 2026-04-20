require "cgi"
cgi = CGI.new

# Access a single parameter
value = cgi["field_name"]          # => "123"
cgi["flowerpot"]                   # => ""

# List, test, and manipulate parameters
fields = cgi.keys                     # => ["field_name"]
cgi.has_key?("field_name")          # => true
cgi.include?("field_name")          # => true
cgi.include?("flowerpot")           # => false
