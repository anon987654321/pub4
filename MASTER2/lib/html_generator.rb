# frozen_string_literal: true

module MASTER
  module Generators
    module HTML
      extend self

      RULES = [
        "Semantic HTML5 only",
        "No div soup - use semantic elements",
        "Minimal attributes (only what's needed)",
        "Progressive enhancement",
        "Accessible by default (WCAG 2.2 AAA)"
      ].freeze

      TEMPLATE = <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>{{title}}</title>
          <style>
            {{styles}}
          </style>
        </head>
        <body>
          {{content}}
        </body>
        </html>
      HTML

      def generate(title:, content:, styles: "")
        html = TEMPLATE
          .gsub("{{title}}", title)
          .gsub("{{content}}", content)
          .gsub("{{styles}}", styles)

        Result.ok(html: html)
      end

      def validate(html)
        errors = []

        # Check semantic structure
        errors << "Missing semantic elements" if html !~ /<(header|nav|main|article|section|aside|footer)/

        # Check for div soup
        div_count = html.scan(/<div/).length
        errors << "Too many divs (#{div_count}) - use semantic HTML" if div_count > 10

        # Check accessibility
        errors << "Images missing alt text" if html =~ /<img(?![^>]*alt=)/
        errors << "Form inputs missing labels" if html =~ /<input(?![^>]*aria-label)/

        errors.empty? ? Result.ok : Result.err(errors.join(", "))
      end
    end
  end
end
