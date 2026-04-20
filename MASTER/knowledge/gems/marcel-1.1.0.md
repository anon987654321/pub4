# Magic bytes onlyMarcel::MimeType.for Pathname.new("example.gif")
# => "image/gif"

File.open "example.gif" do |file|
  Marcel::MimeType.for file
end
# => "image/gif"

# Magic bytes with filename fallback
Marcel::MimeType.for Pathname.new("unrecognisable-data"), name: "example.pdf"
# => "application/pdf"

# Extension only
Marcel::MimeType.for extension: ".pdf"
# => "application/pdf"

# All three factors
Marcel::MimeType.for Pathname.new("unrecognisable-data"), name: "example", declared_type: "image/png"
# => "image/png"

# Fallback
Marcel::MimeType.for StringIO.new(File.read "unrecognisable-data")
# => "application/octet-stream"
