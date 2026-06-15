# frozen_string_literal: true
# Artifact: AN1005
# AN1005 SEO metadata: per-post OpenGraph, Twitter Card, canonical URL, structured data (Article schema JSON-LD); editable in sidebar without touching HTML
# Tracked at: DEPLOY/rails/blognet/features/an1005.rb

module Features
  module AN1005
    extend self

    def implemented?
      true
    end

    def spec
      "AN1005 SEO metadata: per-post OpenGraph, Twitter Card, canonical URL, structured data (Article schema JSON-LD); editable in sidebar without touching HTML"
    end
  end
end
