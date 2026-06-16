# frozen_string_literal: true

require "rexml/document"

XML_PATH = "mydoc.xml"

unless File.readable?(XML_PATH)
  warn "Cannot read #{XML_PATH}"
  exit 1
end

File.open(XML_PATH) do |file|
  # Parse the XML into a DOM‑style document
  doc = REXML::Document.new(file)

  # Iterate over all direct children of the root element
  doc.root.elements.each do |elem|
    puts "Element: #{elem.name}"
  end
end