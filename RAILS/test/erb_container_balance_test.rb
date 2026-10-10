# frozen_string_literal: true

require "minitest/autorun"

# Rails 8.2 compiles ERB through Herb, which refuses a template whose container
# tag is opened and not closed ("Opening tag <div> doesn't have a matching
# closing tag"). The older parser let it through, so amber's item page lost a
# </div> and bsdports' port page lost its </article> and rendered fine until the
# upgrade turned each into a 500 on every request.
#
# This counts opening and closing container tags per template, after the ERB
# tags and comments are removed, so a mismatch is caught without booting Rails.
# A template that opens a tag in one branch and closes it in another is the
# false positive to look for; if one appears, close the tag in both branches
# rather than weakening the count.
class ErbContainerBalanceTest < Minitest::Test
  RAILS = File.expand_path("..", __dir__)
  CONTAINERS = %w[div article section main nav header footer aside ul ol form details table].freeze

  def strip_erb(source)
    source.gsub(/<%#.*?%>/m, "").gsub(/<%.*?%>/m, "").gsub(/<!--.*?-->/m, "")
          .gsub(%r{<(script|style|pre)\b.*?</\1>}m, "")
  end

  def imbalances(source)
    text = strip_erb(source)
    CONTAINERS.filter_map do |tag|
      opened = text.scan(%r{<#{tag}(?=[\s>])[^>]*[^/>]>|<#{tag}>}).size
      closed = text.scan(%r{</#{tag}>}).size
      "#{tag}: #{opened} opened, #{closed} closed" unless opened == closed
    end
  end

  def test_the_counter_flags_an_unclosed_container
    refute_empty imbalances("<article>\n  <div>\n  </div>\n")
    assert_empty imbalances("<article>\n  <% if x %><div class=\"a\"></div><% end %>\n</article>\n")
    assert_empty imbalances("<div><%# <div> in a comment %></div>")
  end

  def test_every_app_template_closes_the_containers_it_opens
    files = Dir[File.join(RAILS, "*", "**", "app", "views", "**", "*.html.erb")].reject { |f| f.include?("/node_modules/") }
    refute_empty files

    offenders = files.filter_map do |file|
      found = imbalances(File.read(file, encoding: "UTF-8"))
      "#{file.delete_prefix("#{RAILS}/")} — #{found.join(', ')}" unless found.empty?
    end

    assert_empty offenders, "templates with unbalanced container tags:\n  #{offenders.join("\n  ")}"
  end
end
