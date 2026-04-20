doc = Loofah.html5_fragment(unsafe_html).scrub!(:prune)
doc.to_s   # → sanitized HTML
doc.text   # → plain text
