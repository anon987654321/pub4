# Create a markup object with 2‑space indentation.
builder = Builder::XmlMarkup.new(indent: 2)

# Build XML by invoking methods that correspond to element names.
xml = builder.person do |b|
  b.name  "Jim"
  b.phone "555-1234"
end

puts xml
