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
          fix: "gem install bundler --no-document",
        }
      end

      if openbsd?
        unless nokogiri_configured?
          issues << {
            problem: "Nokogiri not configured for OpenBSD system libraries",
            fix: "bundle config set build.nokogiri --use-system-libraries",
          }
        end

        unless system_headers_accessible?
          issues << {
            problem: "OpenBSD system headers not accessible",
            fix: "verify /usr/include exists (should be in base system)",
          }
        end
      end

      unless platform_in_lockfile?
        issues << {
          problem: "Gemfile.lock missing ruby platform",
          fix: "bundle lock --add-platform ruby",
        }
      end

      issues
    end

    def print_diagnostics
      issues = diagnose
      return true if issues.empty?

      issues.each do |issue|
        warn "  - #{issue[:problem]}"
        warn "    fix: #{issue[:fix]}"
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

    # True when running inside an OpenBSD vmm(4)/vmd(8) virtual machine.
    def vmm_guest?
      return false unless openbsd?

      `sysctl -n hw.product 2>/dev/null`.strip.include?("VMM")
    rescue StandardError
      false
    end

    # True when hostname resolves to the openbsd.amsterdam provider domain.
    def openbsd_amsterdam?
      return false unless vmm_guest?

      `hostname 2>/dev/null`.strip.end_with?(".openbsd.amsterdam")
    rescue StandardError
      false
    end

    def provider
      return "openbsd.amsterdam" if openbsd_amsterdam?
      return "vmm/vmd (unknown host)" if vmm_guest?

      "bare metal / unknown"
    end

    def hypervisor
      vmm_guest? ? "vmm(4)/vmd(8)" : "bare metal"
    end

    # CPU core count -- read once and cached.
    def cpu_cores
      @cpu_cores ||= read_cpu_cores
    end

    # Free memory in MB -- re-read each call (live pressure indicator).
    def free_mem_mb
      read_free_mem_mb
    end

    # Terse compute badge for the REPL prompt: "8c*862M"
    # Cached for cores; live for memory so pressure is visible.
    def compute_badge
      cores = cpu_cores
      free  = free_mem_mb
      return nil unless cores || free

      parts = []
      parts << "#{cores}c"   if cores
      parts << "#{free}M"    if free
      parts.join("*")
    end

    def total_mem_mb
      @total_mem_mb ||= read_total_mem_mb
    end

    def summary
      return nil unless openbsd?

      issues = diagnose
      if issues.empty?
        "OpenBSD #{openbsd_version} -- all checks passed"
      else
        "OpenBSD #{openbsd_version} -- #{issues.size} issue(s) found"
      end
    end

    private

    def read_cpu_cores
      if openbsd?
        n = `sysctl -n hw.ncpu 2>/dev/null`.strip.to_i
      else
        n = `nproc 2>/dev/null`.strip.to_i
        n = `grep -c processor /proc/cpuinfo 2>/dev/null`.strip.to_i if n.zero?
      end
      n.positive? ? n : nil
    rescue StandardError
      nil
    end

    def read_free_mem_mb
      if openbsd?
        pages     = `sysctl -n vm.uvmexp.free 2>/dev/null`.strip.to_i
        page_size = `sysctl -n hw.pagesize 2>/dev/null`.strip.to_i
        page_size = 4096 if page_size.zero?
        bytes     = pages * page_size
      else
        kb   = `grep MemAvailable /proc/meminfo 2>/dev/null`.scan(/\d+/).first.to_i
        bytes = kb * 1024
      end
      bytes.positive? ? bytes / (1024 * 1024) : nil
    rescue StandardError
      nil
    end

    def read_total_mem_mb
      if openbsd?
        bytes = `sysctl -n hw.physmem 2>/dev/null`.strip.to_i
      else
        kb    = `grep MemTotal /proc/meminfo 2>/dev/null`.scan(/\d+/).first.to_i
        bytes = kb * 1024
      end
      bytes.positive? ? bytes / (1024 * 1024) : nil
    rescue StandardError
      nil
    end

    def uname_s
      `uname -s 2>/dev/null`.strip
    rescue StandardError
      ""
    end
  end
end
