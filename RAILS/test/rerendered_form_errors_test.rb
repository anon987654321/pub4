# frozen_string_literal: true

require "minitest/autorun"

# A controller that answers a failed save with `render :x, status:
# :unprocessable_entity` owes the visitor the reason. The only other signal is
# the red border `.field_with_errors` draws, which says which field and not why.
#
# Measured 2026-09-13: 36 such re-renders, 6 without a message. amber's signup
# was the worst of them — the controller saved into a local, so the view built
# a fresh User.new and a taken email came back as an empty form.
#
# A view passes when it, or a partial it renders by name, reads `.errors` or
# renders an errors partial.
class RerenderedFormErrorsTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  APPS = %w[amber brgen bsdports shared].freeze
  SHOWS_ERRORS = /render[^%]*errors|\.errors\b|error_messages/
  RERENDER = /render\s+:(\w+),\s*status:\s*:unprocessable_(?:entity|content)/

  def roots
    APPS.map { |app| File.join(ROOT, app) } + Dir.glob(File.join(ROOT, "brgen/engines/*"))
  end

  def find_view(root, name)
    Dir.glob(File.join(root, "app/views/#{name}.html.erb")).first ||
      Dir.glob(File.join(ROOT, "{#{APPS.join(',')}}/{app,engines/*/app}/views/#{name}.html.erb")).first
  end

  def rendered_partials(root, controller_path, source)
    source.scan(/render\s*\(?\s*(?:partial:\s*)?["']([\w\/]+)["']/).flatten.filter_map do |name|
      path = name.include?("/") ? name.sub(%r{([^/]+)\z}, '_\1') : "#{controller_path}/_#{name}"
      find_view(root, path)
    end
  end

  def test_every_rerendered_form_shows_its_errors
    checked = 0
    silent = roots.flat_map do |root|
      Dir.glob(File.join(root, "app/controllers/**/*_controller.rb")).flat_map do |controller|
        controller_path = controller.delete_prefix("#{root}/app/controllers/").delete_suffix("_controller.rb")
        File.read(controller).scan(RERENDER).flatten.uniq.filter_map do |action|
          view = find_view(root, "#{controller_path}/#{action}")
          next unless view

          checked += 1
          source = File.read(view)
          texts = [source] + rendered_partials(root, controller_path, source).map { |partial| File.read(partial) }
          next if texts.any? { |text| text.match?(SHOWS_ERRORS) }

          "#{controller.delete_prefix("#{ROOT}/")} render :#{action} -> #{view.delete_prefix("#{ROOT}/")}"
        end
      end
    end

    assert_operator checked, :>=, 30, "found almost no re-rendered forms — the scan is broken, not the tree"
    assert_empty silent, "A form re-rendered on a failed save with no error message:\n#{silent.join("\n")}"
  end
end
