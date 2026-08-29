# frozen_string_literal: true

require "minitest/autorun"
require "net/http"
require "socket"
require "yaml"
require_relative "../gates/lib/fleet"

# Per-app function + layout inventory. Each YAML row is one falsifiable check:
# a file must contain (or omit) a marker, or a live GET must render one.
# The inventories are the list of things we test; this file is the instrument.
#
#   ruby RAILS/test/function_layout_test.rb
#
# Live rows skip (do not fail) when the app port is closed, matching the rest
# of the gate suite. Source rows always run.
class FunctionLayoutTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  DATA = File.join(ROOT, "test", "data", "function_layout")
  APPS = %w[brgen amber bsdports].freeze
# From apps.yml rather than restated here. A literal map is a second
# inventory, and a test carrying one asserts against a number that can stop
# being true without the test noticing.
PORTS = Fleet.app_ports

  def inventories
    @inventories ||= APPS.to_h do |app|
      path = File.join(DATA, "#{app}.yml")
      assert File.file?(path), "missing inventory #{path.sub("#{ROOT}/", "")}"
      doc = YAML.safe_load_file(path)
      assert_equal app, doc["app"]
      [app, Array(doc["checks"])]
    end
  end

  def test_each_app_inventory_is_in_the_agreed_band
    inventories.each do |app, checks|
      ids = checks.map { |c| c.fetch("id") }
      assert_equal ids, ids.uniq, "#{app}: duplicate check ids"
      n = checks.size
      assert_operator n, :>=, 50, "#{app}: #{n} checks is below the 50 floor"
      assert_operator n, :<=, 200, "#{app}: #{n} checks is above the 200 ceiling"
    end
  end

  def test_source_markers_are_present
    failures = []
    inventories.each do |app, checks|
      checks.each do |check|
        next if check["live"]

        failures.concat(run_source(app, check))
      end
    end
    assert_empty failures, failures.join("\n")
  end

  def test_live_pages_when_the_app_is_up
    failures = []
    measured = 0
    inventories.each do |app, checks|
      port = PORTS.fetch(app)
      next unless port_open?(port)

      checks.each do |check|
        spec = check["live"]
        next unless spec

        measured += 1
        failures.concat(run_live(app, check, port, spec))
      end
    end
    skip "no function-layout live ports open" if measured.zero?
    assert_empty failures, failures.join("\n")
  end

  private

  def run_source(app, check)
    id = "#{app}/#{check.fetch("id")}"
    bodies = source_bodies(check)
    return ["#{id}: no files matched #{check["in"].inspect}"] if bodies.empty?

    joined = bodies.join("\n")
    fails = []
    Array(check["has"]).each do |needle|
      n = needle.to_s
      fails << "#{id}: missing #{n.inspect}" unless joined.include?(n)
    end
    Array(check["lack"]).each do |needle|
      n = needle.to_s
      fails << "#{id}: forbidden #{n.inspect}" if joined.include?(n)
    end
    Array(check["re"]).each do |pattern|
      fails << "#{id}: no match /#{pattern}/" unless joined.match?(Regexp.new(pattern))
    end
    fails
  end

  def source_bodies(check)
    Array(check.fetch("in")).flat_map do |rel|
      path = File.join(ROOT, rel)
      if rel.include?("*")
        Dir.glob(path).map { |p| File.file?(p) ? File.read(p) : "" }
      else
        File.file?(path) ? [File.read(path)] : []
      end
    end
  end

  def run_live(app, check, port, spec)
    id = "#{app}/#{check.fetch("id")}"
    path = spec.fetch("path")
    host = spec["host"] || PORTS.key(port) && default_host(app)
    response = http_get(port, path, host)
    fails = []
    want = Integer(spec.fetch("status", 200))
    unless response.code.to_i == want
      fails << "#{id}: HTTP #{response.code} want #{want} at #{path}"
      return fails
    end
    body = response.body.to_s.encode("UTF-8", invalid: :replace, undef: :replace)
    Array(spec["has"]).each do |needle|
      n = needle.to_s
      fails << "#{id}: live missing #{n.inspect}" unless body.include?(n)
    end
    Array(spec["lack"]).each do |needle|
      n = needle.to_s
      fails << "#{id}: live forbidden #{n.inspect}" if body.include?(n)
    end
    fails
  end

  def default_host(app)
    { "brgen" => "brgen.no", "amber" => "127.0.0.1", "bsdports" => "127.0.0.1" }.fetch(app)
  end

  def http_get(port, path, host)
    http = Net::HTTP.new("127.0.0.1", port)
    http.open_timeout = 4
    http.read_timeout = 8
    req = Net::HTTP::Get.new(path)
    req["Host"] = host
    http.request(req)
  end

  def port_open?(port)
    Socket.tcp("127.0.0.1", port, connect_timeout: 0.4).close
    true
  rescue StandardError
    false
  end
end
