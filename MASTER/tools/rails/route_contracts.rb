# frozen_string_literal: true

# Route contracts: what each GET route answers an anonymous visitor, recorded
# from a running app and checked against any other running copy of it.
#
# This is the first piece of the pub5 acceptance harness (TODO.md, "pub5 —
# Phase 0"): a port is done for an app when its contracts pass against the
# ported app. It records only what should survive a rewrite — status,
# redirect target, media type, title, first heading, landmark elements and
# form actions — and normalises numeric ids so seeded data does not churn it.
#
#   ruby MASTER/tools/rails/route_contracts.rb record bsdports http://127.0.0.1:3311 [--host bsdports.org]
#   ruby MASTER/tools/rails/route_contracts.rb check  bsdports http://127.0.0.1:3311 [--host bsdports.org]
#
# Paths come from MASTER/checks/data/route_manifest.yml; routes with dynamic
# segments are skipped until a seeded-record lookup exists.

require "net/http"
require "uri"
require "yaml"

module RouteContracts
  ROOT = File.expand_path("../../..", __dir__)
  MANIFEST = File.join(ROOT, "MASTER", "checks", "data", "route_manifest.yml")
  DIR = File.join(ROOT, "MASTER", "checks", "data", "route_contracts")
  LANDMARKS = %w[header nav main aside footer form dialog].freeze
  TIMEOUT = 30
  # Framework routes (Action Mailbox conductor and ingress) differ by
  # environment and are not product behaviour; development answers 500 there.
  FRAMEWORK = "/rails/"

  # The app under test and where it answers. host is sent as the Host header; a
  # comma list names the app's other hosts too (brgen's verticals answer only on
  # their own subdomains, which the route manifest does not record).
  Target = Data.define(:app, :base, :host) do
    def hosts = host.to_s.split(",").then { |list| list.empty? ? [nil] : list }
  end

  module_function

  def paths(app)
    routes = YAML.load_file(MANIFEST).dig("apps", app, "routes")
    abort "route_contracts: #{app} is not in the manifest" unless routes

    routes.values.flatten.uniq.reject { |path| dynamic?(path) || path.start_with?(FRAMEWORK) }.sort
  end

  def dynamic?(path) = path.include?(":") || path.include?("*")

  def contract_path(app) = File.join(DIR, "#{app}.yml")

  # One anonymous GET, no redirect following: the redirect is part of the contract.
  def fetch(target, path, host = target.hosts.first)
    uri = URI.join(target.base, path)
    request = Net::HTTP::Get.new(uri)
    request["Host"] = host if host
    request["Accept"] = "text/html,application/json;q=0.9,*/*;q=0.8"
    options = { use_ssl: uri.scheme == "https", read_timeout: TIMEOUT, open_timeout: TIMEOUT }
    Net::HTTP.start(uri.host, uri.port, **options) { |http| http.request(request) }
  end

  def describe(response)
    type = response["Content-Type"].to_s.split(";").first.to_s
    row = { "status" => response.code.to_i, "type" => type }
    row["location"] = normalise(URI(response["Location"]).request_uri) if response["Location"]
    return row unless type == "text/html"

    row.merge(page(decoded(response.body)))
  end

  # Net::HTTP hands back bytes; without UTF-8 the YAML stores Norwegian titles as !binary.
  def decoded(body) = body.to_s.dup.force_encoding(Encoding::UTF_8).scrub

  def page(html)
    {
      "title" => text(html[%r{<title[^>]*>(.*?)</title>}m, 1]),
      "heading" => text(html[%r{<h1[^>]*>(.*?)</h1>}m, 1]),
      "landmarks" => LANDMARKS.select { |tag| html.match?(/<#{tag}[\s>]/) },
      "forms" => html.scan(/<form[^>]*\saction="([^"]*)"/).flatten.map { |action| normalise(action) }.uniq.sort,
    }.compact
  end

  def text(fragment)
    return unless fragment

    cleaned = fragment.gsub(/<[^>]+>/, " ").gsub(/&nbsp;|&#160;/, " ").gsub(/\s+/, " ").strip
    cleaned.empty? ? nil : normalise(cleaned)
  end

  # Seeded ids and counts move between databases; the shape must not.
  def normalise(value) = value.gsub(/\d+/, "N")

  # pinned maps a path to the host its contract was recorded on.
  def observe(target, pinned = {})
    paths(target.app).to_h do |path|
      [path, answer(target, path, pinned[path])]
    rescue StandardError => e
      [path, { "error" => e.class.name }]
    end
  end

  # The first host that does not 404 answers for the path, and the row names it
  # when it is not the primary host; a path every host 404s keeps the primary's.
  def answer(target, path, pinned)
    primary = target.hosts.first
    (pinned ? [pinned] : target.hosts).each do |host|
      row = describe(fetch(target, path, host))
      next if row["status"] == 404 && !pinned

      return host == primary ? row : row.merge("host" => host)
    end
    describe(fetch(target, path, primary))
  end

  def record(target)
    observed = observe(target)
    Dir.mkdir(DIR) unless Dir.exist?(DIR)
    contract = { "schema" => 1, "app" => target.app, "host" => target.host, "routes" => observed }
    File.write(contract_path(target.app), YAML.dump(contract))
    observed
  end

  # Every field that differs, per path; a path missing on either side is a difference.
  def compare(expected, actual)
    (expected.keys | actual.keys).sort.filter_map do |path|
      detail = difference(expected[path], actual[path])
      [path, detail] if detail
    end
  end

  def difference(want, got)
    return "missing from the target" unless got
    return "not in the recorded contract" unless want

    fields = (want.keys | got.keys).reject { |key| want[key] == got[key] }
    fields.map { |key| "#{key}: #{want[key].inspect} -> #{got[key].inspect}" }.join("; ") if fields.any?
  end

  def check(target)
    recorded = YAML.load_file(contract_path(target.app))
    pinned = recorded["routes"].filter_map { |path, row| [path, row["host"]] if row["host"] }.to_h
    compare(recorded["routes"], observe(target.with(host: target.host || recorded["host"]), pinned))
  end

  def summary(observed)
    tally = observed.values.map { |row| row["status"] || row["error"] }.tally.sort_by { |status, _count| status.to_s }
    tally.map { |key, count| "#{key}: #{count}" }.join(", ")
  end
end

if $PROGRAM_NAME == __FILE__
  mode, app, base = ARGV.first(3)
  host = ARGV.include?("--host") ? ARGV[ARGV.index("--host") + 1] : nil
  usage = "usage: route_contracts.rb record|check APP BASE_URL [--host HOST]"
  abort usage unless %w[record check].include?(mode) && base
  target = RouteContracts::Target.new(app:, base:, host:)

  if mode == "record"
    observed = RouteContracts.record(target)
    puts "#{app}: #{observed.size} routes recorded (#{RouteContracts.summary(observed)})"
    puts "wrote #{RouteContracts.contract_path(app).delete_prefix("#{RouteContracts::ROOT}/")}"
  else
    differences = RouteContracts.check(target)
    differences.each { |path, detail| puts "#{path}  #{detail}" }
    puts "#{app}: #{differences.empty? ? 'every route matches its contract' : "#{differences.size} route(s) differ"}"
    exit(differences.empty? ? 0 : 1)
  end
end
