require "marcel"

# Pathname of the target file.
path = Pathname.new("example.gif")

# Detect MIME type from magic bytes.
mime_type = Marcel::MimeType.for(path)

puts mime_type # => "image/gif"
