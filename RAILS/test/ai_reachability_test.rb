# frozen_string_literal: true

require "minitest/autorun"

# A route with a view, a controller action, and no link is a feature that exists
# and cannot be found. amber had two — the declutter guide and the occasion map,
# reachable only by typing the URL — while its README described the AI surface as
# a shipped feature.
#
# This asserts the class rather than the two instances, so fixing one is not a
# failure and adding a third unlinked page is.
class AiReachabilityTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  AMBER = File.join(ROOT, "amber")

  # Named routes whose target is a page rather than a mutation. A POST-only
  # endpoint is reached by a form, not by a link, so it is not in scope.
  def ai_get_routes
    routes = File.read(File.join(AMBER, "config/routes.rb"))
    routes.lines.filter_map do |line|
      next unless line =~ /^\s*get\s/
      next unless (name = line[/as: :(ai_\w+)/, 1])

      name
    end.uniq.sort
  end

  def linkable_sources
    @linkable_sources ||= (Dir.glob(File.join(AMBER, "app/views/**/*.erb")) +
                           Dir.glob(File.join(AMBER, "app/helpers/**/*.rb"))).map do |path|
      # Comments stripped: a view that explains why a link was removed would
      # otherwise count as the link.
      File.read(path, encoding: "UTF-8").gsub(/<%#.*?%>/m, "").gsub(/^\s*#.*$/, "")
    end.join
  end

  def test_every_ai_page_is_reachable_from_some_view
    unreachable = ai_get_routes.reject { |name| linkable_sources.include?("#{name}_path") }

    assert_empty unreachable,
                 "these AI pages have a route and a view and are linked from nowhere, so they " \
                 "can only be reached by typing the URL: #{unreachable.join(', ')}"
  end

  # The inverse: a link to a route that does not exist is a 500 waiting for a
  # click, and `link_to` does not fail until the path helper is called.
  def test_every_ai_link_points_at_a_declared_route
    declared = File.read(File.join(AMBER, "config/routes.rb")).scan(/as: :(ai_\w+)/).flatten.uniq
    linked = linkable_sources.scan(/\b(ai_\w+)_path\b/).flatten.uniq

    assert_empty linked - declared, "linked but not routed"
  end

  # Each AI page must have a template, or the link 500s on arrival.
  def test_every_ai_page_has_a_template
    actions = File.read(File.join(AMBER, "config/routes.rb"))
                  .scan(/get\s+"[^"]*",\s*to:\s*"ai#(\w+)"/).flatten.uniq
    missing = actions.reject do |action|
      Dir.glob(File.join(AMBER, "app/views/ai/#{action}.html*")).any?
    end

    assert_empty missing, "routed AI actions with no template"
  end
end
