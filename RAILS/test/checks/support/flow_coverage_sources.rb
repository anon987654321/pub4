# frozen_string_literal: true

# The constants and readers flow_coverage_test.rb shares with the tests split
# out of it to keep each file under its length ceiling.
module FlowCoverageSources
  ROOT = File.expand_path("../../../..", __dir__)
  FLOWS = YAML.safe_load_file(File.join(ROOT, "MASTER", "checks", "data", "flows.yml")).fetch("flows")
  APPS = YAML.safe_load_file(File.join(ROOT, "RAILS", "apps.yml")).fetch("apps").keys
  # The flows run against served apps; an app marked deployed: false has none yet.
  FLEET = Deploy::Inventory.new(root: ROOT).app_names

  STEP_KEYS = %w[
    name get post host params expect_status expect_final_path expect_body expect_any forbid_body
    count number capture capture_final_path needs mail accept asset
  ].freeze
  FLOW_KEYS = %w[id app host description requires_data requires_credentials mutates steps assert].freeze

  def writes?(flow) = flow["steps"].any? { |step| step.key?("post") }

  # --- the data ---------------------------------------------------------------

  # A $name in a path, a parameter or a pattern must have been produced by an
  # earlier step (capture, capture_final_path, a mail capture), be one of the
  # per-run values FlowJourney binds ($unique and the throwaway passwords), or be
  # a credential the flow declares. Otherwise the request goes out with the
  # literal "$name" and the failure reads as a broken page.
  RUN_BOUND = %w[unique flow_password flow_wrong_password flow_new_password].freeze

  # vps-deploy runs flow_journey against the apps it has just restarted, and the
  # port it probes serves production. A journey that signs up, posts or orders
  # without being told to stay off that host would write test rows into the live
  # database on every deploy.
  NO_WRITE_NEEDED = %w[master_unlock_refuses_a_wrong_token].freeze

  # brgen is one app and eight hosts. A guest can write on every vertical host
  # below; maps is the one read-only exception (a check-in needs a place, and a
  # fresh database has none), listed so that a new maps write flow has to delete
  # the exception rather than leave it standing.
  VERTICAL_WRITES = {
    "brgen.no" => "core: posts, votes, comments, messenger, sign-up, sign-in",
    "markedsplass.brgen.no" => "marketplace: list an item, cart",
    "takeaway.brgen.no" => "takeaway: order",
    "dating.brgen.no" => "dating: like",
    "radio.brgen.no" => "playlist: create",
    "tv.brgen.no" => "tv: subscribe",
  }.freeze
  READ_ONLY_VERTICALS = %w[maps.brgen.no].freeze

  def flow_hosts(flow)
    ([flow["host"]] + flow["steps"].select { |s| s.key?("post") }.map { |s| s["host"] }).compact.uniq
  end

  def with_ports_closed
    original = CrawlSupport.method(:port_open?)
    CrawlSupport.define_singleton_method(:port_open?) { |*| false }
    yield
  ensure
    CrawlSupport.define_singleton_method(:port_open?, original)
  end

  def with_env(pairs)
    saved = pairs.keys.to_h { |key| [key, ENV[key]] }
    pairs.each { |key, value| ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| ENV[key] = value }
  end

  def check_with_result
    check = Deploy::FlowJourneyCheck.new
    check.instance_variable_set(:@result, Deploy::CheckResult.new)
    check
  end

  def check_failures(check) = check.instance_variable_get(:@result).failures

  def response(body, path: "/", code: 200)
    Deploy::FlowJourneyCheck::FlowClient::Response.new(code:, body:, final_url: "http://brgen.no#{path}", redirects: [])
  end

  def strings_in(value)
    case value
    when String then [value]
    when Hash then value.flat_map { |k, v| strings_in(k) + strings_in(v) }
    when Array then value.flat_map { |v| strings_in(v) }
    else []
    end
  end
end
