# frozen_string_literal: true

module MASTER
  # Platform detection and remediation advice for OpenBSD gem installation issues
  module PlatformCheck
    extend self

    def openbsd?
      RUBY_PLATFORM.include?("openbsd") || (uname_s == "OpenBSD")
    end

    def bundler_available?
      system("gem", "list", "-i", "bundler", out: File::NULL, err: File::NULL)
    end

    def nokogiri_configured?
      config_output = `bundle config build.nokogiri 2>/dev/null`.strip
      config_output.include?("use-system-libraries")
    rescue StandardError
      false
    end

    def platform_in_lockfile?
      lockfile = File.join(MASTER.root, "Gemfile.lock")
      return true unless File.exist?(lockfile)

      content = File.read(lockfile)
      content.include?("PLATFORMS") && (content.include?("  ruby") || content.include?(RUBY_PLATFORM))
    rescue StandardError
      true
    end

    def system_headers_accessible?
      return true unless openbsd?
      File.exist?("/usr/include/libxml2/libxml/tree.h")
    end

    def diagnose
      issues = []

      unless bundler_available?
        issues << {
          problem: "Bundler not installed",
          fix: "gem install bundler --no-document"
        }
      end

      if openbsd?
        unless nokogiri_configured?
          issues << {
            problem: "Nokogiri not configured for OpenBSD system libraries",
            fix: "bundle config build.nokogiri --use-system-libraries"
          }
        end

        unless system_headers_accessible?
          issues << {
            problem: "OpenBSD system headers not accessible",
            fix: "verify /usr/include exists (should be in base system)"
          }
        end
      end

      unless platform_in_lockfile?
        issues << {
          problem: "Gemfile.lock missing ruby platform",
          fix: "bundle lock --add-platform ruby"
        }
      end

      issues
    end

    def print_diagnostics
      issues = diagnose
      return true if issues.empty?

      issues.each do |issue|
        $stderr.puts "  - #{issue[:problem]}"
        $stderr.puts "    fix: #{issue[:fix]}"
      end
      false
    end

    def openbsd_version
      return nil unless openbsd?
      version = `uname -r 2>/dev/null`.strip
      version.empty? ? "unknown" : version
    rescue StandardError
      "unknown"
    end

    def summary
      return nil unless openbsd?

      issues = diagnose
      if issues.empty?
        "OpenBSD #{openbsd_version} — all checks passed"
      else
        "OpenBSD #{openbsd_version} — #{issues.size} issue(s) found"
      end
    end

    private

    def uname_s
      `uname -s 2>/dev/null`.strip
    rescue StandardError
      ""
    end
  end
end
