require "rails/html/sanitizer"

# -------------------------------------------------
# FullSanitizer – strip *all* HTML tags, keep plain text
# -------------------------------------------------
#
# Rails::HTML::FullSanitizer removes every HTML element,
# leaving only the textual content. It is ideal when you
# need to display user‑generated markup as pure text without
# any risk of XSS or layout interference.
#
# Example:
input = <<~HTML
  <b>Bold</b> no more! <a href='more.html'>See more here</a>
HTML

full = Rails::HTML::FullSanitizer.new
# => "Bold no more! See more here"
puts full.sanitize(input)
