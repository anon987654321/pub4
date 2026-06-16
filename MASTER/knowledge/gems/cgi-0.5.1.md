cgi = CGI.new

# Fetch a single parameter (returns "" if missing)
value   = cgi["field_name"]   # => "123"
missing = cgi["flowerpot"]    # => ""

# Inspect the whole set
fields   = cgi.keys                     # => ["field_name"]
present? = cgi.has_key?("field_name")   # => true
present? = cgi.include?("field_name")   # => true
absent?  = cgi.include?("flowerpot")    # => false

# Debug dump (hash of arrays)
debug = cgi.params # => {"field_name"=>["123"]}

# Escape output before embedding in HTML to prevent XSS
escaped = CGI.escapeHTML(value)  # => "123" (HTML‑escaped)
