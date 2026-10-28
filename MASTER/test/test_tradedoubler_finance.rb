# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "digest"
require "fileutils"
require "tmpdir"
require_relative "../lib/finance/tradedoubler"

class TestTradedoublerFinance < Minitest::Test
  Service = Master::Finance::Tradedoubler
  Response = Struct.new(:code, :body)

  def setup
    @root = Dir.mktmpdir("tradedoubler-finance")
    @master_root = File.join(@root, "MASTER")
    FileUtils.mkdir_p(File.join(@master_root, "data"))
    @now = Time.utc(2026, 10, 21, 10)
    @env = {}
    @requests = []
    @response = Response.new("200", "[]")
    @transport = lambda do |method:, uri:, request:, body:, headers:|
      @requests << { method:, uri:, body:, headers: }
      @response
    end
    write_sources
    FileUtils.cp(File.join(Master::ROOT, "data", "affiliate_grants.yml"),
                 File.join(@master_root, "data", "affiliate_grants.yml"))
    @service = new_service
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && File.directory?(@root)
  end

  def new_service
    Service.new(root: @root, master_root: @master_root, env: @env,
                clock: -> { @now }, transport: @transport)
  end

  def write_sources
    File.write(File.join(@master_root, "data", "affiliate_sources.yml"), <<~YAML)
      schema: 1
      network: tradedoubler
      claims_api:
        base_url: "https://api.tradedoubler.com/1.0"
        docs_url: "https://dev.tradedoubler.com/claims/publisher/"
        token_env: TRADEDOUBLER_CLAIMS_TOKEN
        page_size: 100
        max_pages: 10
      apps:
        brgen:
          domain: "brgen.no"
          affiliate_site_id: "12345"
          programs: { demo_program: "220" }
        amber:
          domain: "amberapp.art"
          affiliate_site_id: null
          programs: {}
      management_api:
        enabled: false
        reason: "unverified OAuth route"
    YAML
  end

  def grant(scope)
    phrase = {
      "claims.read" => "GRANT tradedoubler.claims.read",
      "claims.prepare" => "GRANT tradedoubler.claims.prepare",
      "claims.submit" => "GRANT tradedoubler.claims.submit",
    }.fetch(scope)
    @service.grant_scope(scope, confirmation: phrase)
  end

  def claim_input(overrides = {})
    {
      "source" => "brgen", "program_key" => "demo_program",
      "timeStampEvent" => "2026-10-20", "eventId" => 17,
      "orderNumber" => "ORDER-123", "orderValue" => "32.00",
      "expectedCommission" => "2.50"
    }.merge(overrides)
  end

  def write_input(value)
    path = File.join(@root, "claim.json")
    File.write(path, JSON.generate(value))
    path
  end

  def test_status_does_not_read_credentials_or_open_network
    env = Object.new
    env.define_singleton_method(:[]) { |_key| raise "credentials must not be inspected for status" }
    service = Service.new(root: @root, master_root: @master_root, env:,
                          clock: -> { @now }, transport: ->(**) { raise "network must not run" })

    state = service.status

    assert_equal false, state.dig("apps", "amber", "affiliate_site_id_configured")
    assert_includes state.fetch("claims_token"), "not inspected"
  end

  def test_claims_read_requires_a_grant_before_credentials_or_network
    env = Object.new
    env.define_singleton_method(:[]) { |_key| raise "credential read before grant" }
    service = Service.new(root: @root, master_root: @master_root, env:,
                          clock: -> { @now }, transport: ->(**) { raise "network before grant" })

    error = assert_raises(Service::ConsentRequired) { service.list_claims }
    assert_match(/grant missing or expired/, error.message)
    assert_empty @requests
  end

  def test_claims_read_uses_documented_endpoint_and_keeps_tokens_out_of_ledger
    @env["TRADEDOUBLER_CLAIMS_TOKEN"] = "a" * 40
    grant("claims.read")
    @response = Response.new("200", [
      { "claimId" => 7, "affiliateSiteId" => "12345", "statusId" => 2,
        "statusName" => "Awaiting approval", "programId" => "220",
        "programName" => "Demo", "timeStampEvent" => "2026-10-20",
        "eventId" => "17", "orderNumber" => "ORDER-PRIVATE",
        "orderValue" => "32.00", "expectedCommission" => "2.50" },
    ].to_json)

    result = @service.list_claims(source: "brgen")

    assert_equal "complete", result.fetch("status")
    assert_equal 1, result.fetch("count")
    assert_equal "ORDER-PRIVATE", result.dig("claims", 0, "orderNumber")
    assert_equal "/1.0/claims;limit=100;offset=0;tdconnect=true", @requests.first.fetch(:uri).path
    assert_includes @requests.first.fetch(:uri).query, "token="
    ledger = File.read(File.join(@root, Service::EVENT_PATH))
    refute_includes ledger, "a" * 40
    refute_includes ledger, "ORDER-PRIVATE"
  end

  def test_prepare_refuses_unconfigured_program_ids
    grant("claims.prepare")
    error = assert_raises(Service::Error) do
      @service.prepare_claim(path: write_input(claim_input("program_key" => "unknown")))
    end
    assert_match(/not configured/, error.message)
  end

  def test_prepare_hashes_the_payload_and_keeps_the_record_private
    grant("claims.prepare")
    result = @service.prepare_claim(path: write_input(claim_input))

    assert_equal "prepared_not_submitted", result.fetch("status")
    assert_match(/\A[0-9a-f]{64}\z/, result.fetch("sha256"))
    prepared = File.join(@root, result.fetch("prepared_file"))
    assert_equal 0o600, File.stat(prepared).mode & 0o777
    body = File.read(prepared)
    refute_includes body, "TRADEDOUBLER_CLAIMS_TOKEN"
    assert_equal result.fetch("sha256"), JSON.parse(body).fetch("payload_sha256")
    assert_empty @requests
  end

  def test_event_17_requires_commission_and_other_events_reject_it
    grant("claims.prepare")
    missing = write_input(claim_input("expectedCommission" => nil))
    assert_raises(ArgumentError) { @service.prepare_claim(path: missing) }

    extra = write_input(claim_input("eventId" => 3, "expectedCommission" => "1.00"))
    assert_raises(ArgumentError) { @service.prepare_claim(path: extra) }
  end

  def test_submit_requires_exact_hash_and_consumes_approval
    @env["TRADEDOUBLER_CLAIMS_TOKEN"] = "b" * 40
    grant("claims.prepare")
    prepared = @service.prepare_claim(path: write_input(claim_input))
    grant("claims.submit")

    assert_raises(Service::ConsentRequired) do
      @service.submit_claim(prepared.fetch("sha256"), confirmation_hash: "0" * 64)
    end
    assert_empty @requests

    @response = Response.new("200", "")
    result = @service.submit_claim(
      prepared.fetch("sha256"), confirmation_hash: prepared.fetch("sha256")
    )

    assert_equal "accepted_for_review_not_approved", result.fetch("status")
    assert_equal "POST", @requests.last.fetch(:method)
    payload = JSON.parse(@requests.last.fetch(:body)).fetch("claims").first
    assert_equal prepared.fetch("sha256"), Digest::SHA256.hexdigest(JSON.generate(payload.sort.to_h))
    refute @service.status.dig("scopes", "claims.submit", "active")
  end

  def test_tampered_duplicate_key_digest_is_refused_before_network
    grant("claims.prepare")
    prepared = @service.prepare_claim(path: write_input(claim_input))
    path = File.join(@root, prepared.fetch("prepared_file"))
    record = JSON.parse(File.read(path))
    record["claim_key_sha256"] = "0" * 64
    File.write(path, JSON.generate(record))

    grant("claims.submit")
    error = assert_raises(Service::Error) do
      @service.submit_claim(prepared.fetch("sha256"), confirmation_hash: prepared.fetch("sha256"))
    end

    assert_match(/duplicate-key digest mismatch/, error.message)
    assert_empty @requests
  end

  def test_duplicate_transaction_is_refused_after_one_submission_attempt
    @env["TRADEDOUBLER_CLAIMS_TOKEN"] = "c" * 40
    grant("claims.prepare")
    prepared = @service.prepare_claim(path: write_input(claim_input))
    grant("claims.submit")
    @response = Response.new("200", "")
    @service.submit_claim(prepared.fetch("sha256"), confirmation_hash: prepared.fetch("sha256"))
    grant("claims.submit")

    error = assert_raises(Service::Error) do
      @service.submit_claim(prepared.fetch("sha256"), confirmation_hash: prepared.fetch("sha256"))
    end

    assert_match(/already attempted/, error.message)
    assert_equal 1, @requests.count { |request| request[:method] == "POST" }
  end

  def test_unconfigured_site_fails_before_credentials_are_read
    env = Object.new
    env.define_singleton_method(:[]) { |_key| raise "token must not be read" }
    @service = Service.new(root: @root, master_root: @master_root, env:,
                           clock: -> { @now }, transport: @transport)
    grant("claims.read")

    error = assert_raises(Service::Error) { @service.list_claims(source: "amber") }
    assert_match(/affiliate_site_id is not configured/, error.message)
    assert_empty @requests
  end
end
