# frozen_string_literal: true

module MASTER
  module AutoInstall
    GEMS = %w[
      ruby_llm
      stoplight
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
      rufus-scheduler
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
          next unless gem.match?(/\A[a-z0-9_-]+\z/)

          system("gem", "install", gem, "--no-document")
        end

        Gem.clear_paths
      end

      def require_gem(name)
        require name
      rescue LoadError
        return if @installed&.dig(name)
        return unless name.to_s.match?(/\A[a-z0-9_-]+\z/)

        @installed ||= {}
        warn "Installing #{name}..."
        @installed[name] = system("gem", "install", name, "--no-document")
        Gem.clear_paths if @installed[name]
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
        system("pkg_info", "-e", "#{name}-*", out: File::NULL, err: File::NULL)
      end

      def install_packages(verbose: false)
        return unless openbsd?

        missing = missing_packages
        return if missing.empty?

        puts "Installing #{missing.size} packages..." if verbose
        valid_packages = missing.grep(/\A[a-z0-9_-]+\z/)
        system("doas", "pkg_add", *valid_packages) unless valid_packages.empty?
      end

      def setup(verbose: false)
        install_packages(verbose: verbose)
        install_gems(verbose: verbose)
      end

      def status
        {
          gems: { installed: GEMS.size - missing_gems.size, missing: missing_gems },
          packages: if openbsd?
                      { installed: OPENBSD_PACKAGES.size - missing_packages.size,
                        missing: missing_packages }
                    end,
        }
      end
    end
  end
end
