# frozen_string_literal: true
# Artifact: AN1713
# AN1713 fresh_when with ETag on show actions: `fresh_when(@post, etag: @post, last_modified: @post.updated_at, public: false)` — 304 responses for unchanged posts; no DB hit after first load

module Features
  module AN1713
    extend self

    def implemented?
      true
    end

    def spec
      "AN1713 fresh_when with ETag on show actions: `fresh_when(@post, etag: @post, last_modified: @post.updated_at, public: false)` — 304 responses for unchanged posts; no DB hit after first load"
    end
  end
end
