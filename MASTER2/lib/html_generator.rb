# frozen_string_literal: true

module HtmlGenerator
  JS_ARRAY_SEPARATOR = ",\n        "

  def self.generate(title:, body:, scripts: [], styles: [])
    styles_html = styles.map { |href| %(<link rel="stylesheet" href="#{escape_attr(href)}">) }.join("\n    ")
    scripts_html = scripts.map { |src| %(<script src="#{escape_attr(src)}"></script>) }.join("\n    ")

    <<~HTML
      <!doctype html>
      <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>#{escape_text(title)}</title>
      #{styles_html.empty? ? "" : "    #{styles_html}\n"}
      #{scripts_html.empty? ? "" : "    #{scripts_html}\n"}
        </head>
        <body>
      #{body}
        </body>
      </html>
    HTML
  end

  def self.format_js_array(values)
    "[\n        #{values.map { |v| v.to_s }.join(JS_ARRAY_SEPARATOR)}\n      ]"
  end

  def self.escape_text(text)
    text.to_s
        .gsub("&", "&amp;")
        .gsub("<", "&lt;")
        .gsub(">", "&gt;")
  end

  def self.escape_attr(text)
    escape_text(text).gsub('"', "&quot;")
  end

  private_class_method :escape_text, :escape_attr
end