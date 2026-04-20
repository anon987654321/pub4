require 'builder'

builder = Builder::XmlMarkup.new
xml = builder.person { |b| b.name('Jim'); b.phone('555-1234') }
# => <person><name>Jim</name><phone>555-1234</phone></person>
