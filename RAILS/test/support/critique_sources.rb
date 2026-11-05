# frozen_string_literal: true

require "yaml"
require_relative "stylesheet_modules"

# The source readers the critique implementation tests share. They were one
# file until it outgrew its length ceiling; the three files read the same sources.
module CritiqueSources
  include StylesheetModules
  ROOT = File.expand_path("../..", __dir__)

  def read(path) = File.read(File.join(ROOT, path))

  def brgen_css_source
    host = read("brgen/app/assets/stylesheets/application.scss")
    features = Dir.glob(File.join(ROOT, "brgen/app/assets/stylesheets/_brgen_*.scss")).sort
                 .map { |path| File.read(path, encoding: "UTF-8") }

    ([host] + features).join("\n")
  end

  # The radio tunnel was split into tunnel, audio and visual modules; the
  # contract is about the radio as a whole, so it reads all three.
  def radio_source
    %w[tunnel audio visual].map { |part| read("brgen/app/javascript/radio_brgen_#{part}.js") }.join("\n")
  end

  def amber_css_source
    host = read("amber/app/assets/stylesheets/application.scss")
    features = Dir.glob(File.join(ROOT, "amber/app/assets/stylesheets/_amber_*.scss")).sort
                 .map { |path| File.read(path, encoding: "UTF-8") }

    ([host] + features).join("\n")
  end

  # These pages render through I18n, so a literal English string stopped being
  # in the template the moment the page was localised — the assertion failed on
  # a view that had got better. Pin the key in the template and the copy in that
  # app's en.yml: the control still has to say this word, and the check survives
  # the next locale. Two assertions in this file were already rewritten for the
  # same reason; the comments above them explain each case.
  def en_value(app, key)
    locale = YAML.safe_load_file(File.join(ROOT, app, "config", "locales", "en.yml")).fetch("en")
    key.split(".").reduce(locale) { |node, segment| node.fetch(segment) }
  end

  def assert_localised(app, template, key, english)
    assert_includes read("#{app}/app/views/#{template}"), %(t("#{key}"))
    assert_equal english, en_value(app, key), "#{app} en.yml #{key} drifted from the copy #{template} promises"
  end
end
