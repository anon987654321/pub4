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
      "policy.frame_ancestors :self",
      "policy.script_src",
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
      path = File.expand_path(relative, @root)
      root_stat = File.lstat(@root)
      unless root_stat.directory? && !root_stat.symlink?
        result.fail("security_headers: root is not a real directory")
        return nil
      end

      root_prefix = "#{@root}#{File::SEPARATOR}"
      unless path.start_with?(root_prefix)
        result.fail("security_headers: source escapes root: #{relative}")
        return nil
      end

      cursor = @root
      components = relative.split(File::SEPARATOR)
      components[0...-1].each do |component|
        cursor = File.join(cursor, component)
        stat = File.lstat(cursor)
        unless stat.directory? && !stat.symlink?
          result.fail("security_headers: parent path is not a real directory for #{relative}")
          return nil
        end
      end

      unless File.exist?(path) || File.symlink?(path)
        result.fail("security_headers: missing #{relative}")
        return nil
      end
      stat = File.lstat(path)
      unless stat.file? && !stat.symlink?
        result.fail("security_headers: refuses non-regular or symlinked source #{relative}")
        return nil
      end

      flags = File::RDONLY
      flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
      File.open(path, flags) do |file|
        opened = file.stat
        current = File.lstat(path)
        unless current.file? && !current.symlink? &&
               current.dev == opened.dev && current.ino == opened.ino
          result.fail("security_headers: source path changed while opening #{relative}")
          return nil
        end

        content = file.read.force_encoding(Encoding::UTF_8)
        unless content.valid_encoding?
          result.fail("security_headers: invalid UTF-8 in #{relative}")
          return nil
        end

        after = File.lstat(path)
        unless after.file? && !after.symlink? &&
               after.dev == opened.dev && after.ino == opened.ino &&
               after.size == opened.size && after.mtime == opened.mtime && after.ctime == opened.ctime
          result.fail("security_headers: source changed while reading #{relative}")
          return nil
        end

        result.checked!
        content
      end
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

      directives = script_source_directives(source)
      unless directives.any? { |directive| directive[:name] == "script_src" }
        result.fail("security_headers: #{label} has no explicit script-src directive")
      end

      directives.each do |entry|
        directive = entry.fetch(:source)
        if directive.match?(/(?:^|[\s,]):https?\b|(?:^|[\s,]):(?:data|blob)\b/i) ||
           directive.match?(/unsafe[-_]eval|unsafe[-_]inline/i) ||
           directive.match?(/["']\*["']|(?:^|[\s,])\*(?:[\s,]|$)|https?:\/\/\*/i) ||
           directive.match?(/\bhttp:\/\/|["'](?:data|blob):|["']https?:["']/i)
          result.fail(
            "security_headers: #{label} has an overly broad #{entry.fetch(:name).tr("_", "-")}: #{directive.strip}"
          )
        end
      end
    end

    # A Ruby DSL call may continue onto following lines. Inspect the complete
    # statement rather than only the first line, and include script-src-elem and
    # script-src-attr because either can override the base script-src policy.
    def script_source_directives(source)
      lines = source.lines
      directives = []
      index = 0

      while index < lines.length
        code = lines[index].split("#", 2).first.to_s
        match = code.match(/^\s*policy\.(script_src(?:_elem|_attr)?)\b/)
        unless match
          index += 1
          next
        end

        statement = [code]
        index += 1
        while index < lines.length
          continuation = lines[index].split("#", 2).first.to_s
          break if continuation.match?(/^\s*(?:policy\.|config\.|end\b)/)

          statement << continuation
          index += 1
        end
        directives << { name: match[1], source: statement.join }
      end

      directives
    end

    def check_relayd_does_not_set_csp(result, source)
      return unless source

      setters = source.lines.select do |line|
        line.match?(/^\s*match\s+response\s+header\s+(?:set|append|remove)\s+["']Content-Security-Policy(?:-Report-Only)?["']/i)
      end
      return if setters.empty?

      result.fail(
        "security_headers: #{RELAYD} must not alter app-owned CSP; " \
        "nonce-bearing policy belongs to Rails: #{setters.map(&:strip).join("; ")}"
      )
    end
  end
end
