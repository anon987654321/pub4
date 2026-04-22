# frozen_string_literal: true

require "open-uri"
require "nokogiri"

# ----------------------------------------------------------------------
# Constants
# ----------------------------------------------------------------------
# Official Nokogiri installation tutorial.
TUTORIAL_URL = "https://nokogiri.org/tutorials/installing_nokogiri.html"

# ----------------------------------------------------------------------
# Public API
# ----------------------------------------------------------------------
# Fetches an HTML document from a URL and returns a +Nokogiri::HTML::Document+.
# On failure it returns +nil+ and logs a concise error message.
#
# @param url [String] Web address to retrieve.
# @return [Nokogiri::HTML::Document, nil]
def fetch_document(url)
  URI.open(url, "User-Agent" => "nokogiri‑scraper/1.0") do |io|
    Nokogiri::HTML(io.read)
  end
rescue OpenURI::HTTPError => e
  warn "❌ HTTP error while fetching #{url}: #{e.message}"
  nil
rescue SocketError, Errno::ECONNREFUSED => e
  warn "❌ Network error while fetching #{url}: #{e.message}"
  nil
rescue StandardError => e
  warn "❌ Unexpected error (#{e.class}) fetching #{url}: #{e.message}"
  nil
end

# Prints navigation links and top‑level headings found in a Nokogiri document.
#
# The method extracts:
# * Navigation items: <nav> → <ul.menu> → <li> → <a>
# * Section headings: <article> → <h2>
#
# @param doc [Nokogiri::HTML::Document] Parsed HTML.
def print_navigation_and_headings(doc)
  nav_links = doc.css("nav ul.menu li a")
  headings  = doc.css("article h2")

  (nav_links + headings).each { |node| puts node.text.strip }
end

# ----------------------------------------------------------------------
# CLI entry point
# ----------------------------------------------------------------------
if (document = fetch_document(TUTORIAL_URL))
  puts "🔎 Navigation & headings from #{TUTORIAL_URL}:"
  puts "------------------------------------------------"
  print_navigation_and_headings(document)
else
  warn "⚠️ Unable to retrieve or parse the tutorial page."
end