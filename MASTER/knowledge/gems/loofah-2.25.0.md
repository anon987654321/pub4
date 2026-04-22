# 1️⃣ Pull the raw HTML from the request parameters.
#    ⚠️ This data is *untrusted* – treat it as potentially malicious.
unsafe_html = params[:html]

# 2️⃣ Parse the HTML into a Loofah fragment and apply the built‑in :prune scrubber.
#    :prune strips any element that isn’t on Loofah’s safe‑list while preserving
#    the allowed content unchanged.
doc = Loofah.html5_fragment(unsafe_html).scrub!(:prune)

# 3️⃣ Render the sanitized HTML.
sanitized = doc.to_s
# => "<p>Safe content …</p>"

# 4️⃣ Extract a plain‑text version (all tags removed).
plain = doc.text
# => "Safe content …"
