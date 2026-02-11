# frozen_string_literal: true

module MASTER
  module AutoInstall
    GEMS = %w[
      ruby_llm
      tty-reader
      tty-prompt
      tty-spinner
      tty-table
      tty-box
      tty-markdown
      tty-progressbar
      tty-cursor
      pastel
      rouge
      falcon
      async-websocket
    ].freeze

    OPENBSD_PACKAGES = %w[
      ruby
      git
      curl
    ].freeze

    class << self
      def missing_gems
        GEMS.reject { |g| gem_installed?(g) }
      end

      def gem_installed?(name)
        Gem::Specification.find_by_name(name)
        true
      rescue Gem::MissingSpecError
        false
      end

      def install_gems(verbose: false)
        missing = missing_gems
        return if missing.empty?

        puts "Installing #{missing.size} gems..." if verbose
        missing.each do |gem|
          # SECURITY: Use array form of system() to prevent shell injection
          system("gem", "install", gem, "--no-document")
        end
      end

      def require_gem(name)
        require name
      rescue LoadError
        return if @installed&.dig(name)
        # SECURITY: Only install gems from the allowlist
        # Convert to string for consistent comparison (GEMS contains strings)
        gem_name = name.to_s
        unless GEMS.include?(gem_name)
          raise ArgumentError, "Gem '#{gem_name}' is not in the allowed GEMS list"
        end
        @installed ||= {}
        $stderr.puts "Installing #{gem_name}..."
        # SECURITY: Use array form of system() to prevent shell injection
        @installed[name] = system("gem", "install", gem_name, "--no-document")
        require name
      end

      def openbsd?
        RUBY_PLATFORM.include?("openbsd")
      end

      def missing_packages
        return [] unless openbsd?
        OPENBSD_PACKAGES.reject { |p| package_installed?(p) }
      end

      def package_installed?(name)
        system("pkg_info -e '#{name}-*' > /dev/null 2>&1")
      end

      def install_packages(verbose: false)
        return unless openbsd?
        missing = missing_packages
        return if missing.empty?

        puts "Installing #{missing.size} packages..." if verbose
        # SECURITY: Package names are from OPENBSD_PACKAGES constant (safe)
        # Using array form for additional safety
        system("doas", "pkg_add", *missing)
      end

      def setup(verbose: false)
        install_packages(verbose: verbose)
        install_gems(verbose: verbose)
      end

      def status
        {
          gems: { installed: GEMS.size - missing_gems.size, missing: missing_gems },
          packages: openbsd? ? { installed: OPENBSD_PACKAGES.size - missing_packages.size, missing: missing_packages } : nil
        }
      end
    end
  end
end
