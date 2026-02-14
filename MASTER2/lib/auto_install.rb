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
          system("gem install #{gem} --no-document")
        end
      end

      def require_gem(name)
        require name
      rescue LoadError
        return if @installed&.dig(name)
        @installed ||= {}
        $stderr.puts "Installing #{name}..."
        @installed[name] = system("gem install #{name} --no-document")
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
        system("doas pkg_add #{missing.join(' ')}")
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
