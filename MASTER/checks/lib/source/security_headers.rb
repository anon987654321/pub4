# frozen_string_literal: true

require_relative "../../support/check_result"

module Deploy
  # Verifies the existing split ownership of pub4's response-security policy.
  #
  # This is a source contract, not a claim about a live response. relayd owns
  # the edge headers; Rails owns nonce-bearing, app-specific CSP. In particular,
  # installing one global CSP at relayd overwrites the app's nonce policy.
  # Whether report-only CSP is enforced on vm23 remains an operator-only seam.
  class SecurityHeadersSourceCheck
    ROOT = File.expand_path("../../../..", __dir__)
    SHARED_HEADERS = "RAILS/__shared/config/initializers/security_headers.rb"
    SHARED_CSP = "RAILS/__shared/config/initializers/content_security_policy.rb"
    MASTER_CSP = "RAILS/master/config/initializers/content_security_policy.rb"
    RELAYD = "OPENBSD/etc/relayd.conf"

    SHARED_HEADER_FRAGMENTS = [
      '"X-Content-Type-Options" => "nosniff"',
      '"X-Frame-Options" => "SAMEORIGIN"',
      '"Referrer-Policy" => "strict-origin-when-cross-origin"',
      '"Cross-Origin-Opener-Policy" => "same-origin"',
      '"X-Permitted-Cross-Domain-Policies" => "none"',
      '"Permissions-Policy" => "accelerometer=',
      '"X-XSS-Protection" => "0"',
    ].freeze

    EDGE_HEADER_FRAGMENTS = [
      'match response header set "Strict-Transport-Security" value "max-age=31536000; includeSubDomains; preload"',
      'match response header set "Referrer-Policy" value "strict-origin"',
      'match response header set "X-Content-Type-Options" value "nosniff"',
      'match response header set "X-XSS-Protection" value "0"',
      'match response header set "Permissions-Policy" value "accelerometer=',
      'match response header remove "X-Frame-Options"',
    ].freeze

    SHARED_CSP_FRAGMENTS = [
      "config.content_security_policy_nonce_generator",
      "config.content_security_policy_nonce_directives = %w[script-src]",
      "policy.object_src :none",
      "policy.script_src :self",
      'policy.report_uri "/csp-reports"',
      'config.content_security_policy_report_only = ENV["PUB4_CSP_ENFORCE"] != "1"',
    ].freeze

    MASTER_CSP_FRAGMENTS = [
      "config.content_security_policy_nonce_generator",
      "policy.object_src :none",
      "policy.frame_ancestors :self, *embed_hosts",
      "https://brgen.no",
      "https://www.brgen.no",
      "https://amberapp.art",
      'config.content_security_policy_report_only = !enforce',
    ].freeze

    def self.run(root: ROOT) = new(root:).run

    def initialize(root: ROOT)
      @root = File.expand_path(root)
    end

    def run
      result = CheckResult.new
      shared_headers = read_source(SHARED_HEADERS, result)
      relayd = read_source(RELAYD, result)
      shared_csp = read_source(SHARED_CSP, result)
      master_csp = read_source(MASTER_CSP, result)

      require_fragments(result, SHARED_HEADERS, shared_headers, SHARED_HEADER_FRAGMENTS)
      require_fragments(result, RELAYD, relayd, EDGE_HEADER_FRAGMENTS)
      require_fragments(result, SHARED_CSP, shared_csp, SHARED_CSP_FRAGMENTS)
      require_fragments(result, MASTER_CSP, master_csp, MASTER_CSP_FRAGMENTS)
      check_script_sources(result, SHARED_CSP, shared_csp)
      check_script_sources(result, MASTER_CSP, master_csp)
      check_relayd_does_not_set_csp(result, relayd)
      result
    end

    private

    def read_source(relative, result)
      path = File.join(@root, relative)
      unless File.file?(path)
        result.fail("security_headers: missing #{relative}")
        return nil
      end

      result.checked!
      File.read(path, encoding: "UTF-8")
    rescue SystemCallError, EncodingError => e
      result.fail("security_headers: cannot read #{relative}: #{e.class}: #{e.message}")
      nil
    end

    def require_fragments(result, label, source, fragments)
      return unless source

      fragments.each do |fragment|
        result.fail("security_headers: #{label} is missing #{fragment.inspect}") unless source.include?(fragment)
      end
    end

    def check_script_sources(result, label, source)
      return unless source

      directives = source.lines.reject { |line| line.lstrip.start_with?("#") }
                        .filter_map { |line| line.split("#", 2).first if line.match?(/^\s*policy\.script_src\b/) }
      if directives.empty?
        result.fail("security_headers: #{label} has no explicit script-src directive")
        return
      end

      directives.each do |directive|
        if directive.match?(/(?:^|[\s,]):https\b|unsafe[-_]eval/i) ||
           directive.match?(/(?:^|[\s,])\*(?:[\s,]|$)/)
          result.fail("security_headers: #{label} has an overly broad script-src: #{directive.strip}")
        end
      end
    end

    def check_relayd_does_not_set_csp(result, source)
      return unless source

      setters = source.lines.select do |line|
        line.match?(/^\s*match\s+response\s+header\s+set\s+["']Content-Security-Policy(?:-Report-Only)?["']/i)
      end
      return if setters.empty?

      result.fail(
        "security_headers: #{RELAYD} must not replace app-owned CSP; " \
        "nonce-bearing policy belongs to Rails: #{setters.map(&:strip).join("; ")}"
      )
    end
  end
end
