# frozen_string_literal: true

module MASTER
  # Auto-installer for dependencies
  # Detects and installs missing packages, gems, and repos
  module AutoInstall
    REPOS_DIR = File.expand_path('~/tmp/repos')
    
    # OpenBSD packages MASTER uses
    OPENBSD_PACKAGES = %w[
      ruby
      git
      curl
      starship
      fzf
      ripgrep
      fd
      bat
      jq
      htop
    ].freeze
    
    # Ruby gems MASTER uses
    GEMS = %w[
      tty-prompt
      tty-spinner
      tty-table
      tty-box
      pastel
      ruby_llm
      async
      async-http
    ].freeze
    
    # GitHub repos to clone for reference/tools
    REPOS = {
      # Ruby CLI frameworks
      'rails/rails' => 'Ruby on Rails',
      'jekyll/jekyll' => 'Static site generator',
      'erikhuda/thor' => 'CLI toolkit',
      'pry/pry' => 'Ruby REPL',
      'rubocop/rubocop' => 'Ruby linter',
      
      # Zsh tools
      'ohmyzsh/ohmyzsh' => 'Zsh framework',
      'zsh-users/zsh-autosuggestions' => 'Zsh autosuggestions',
      'zsh-users/zsh-syntax-highlighting' => 'Zsh syntax highlighting',
      'spaceship-prompt/spaceship-prompt' => 'Zsh prompt',
      
      # CLI references
      'tmuxinator/tmuxinator' => 'Tmux session manager',
      'junegunn/fzf' => 'Fuzzy finder'
    }.freeze

    class << self
      # Check and install all missing dependencies
      def ensure_all(verbose: true)
        results = { packages: [], gems: [], repos: [] }
        
        if openbsd?
          results[:packages] = ensure_packages(verbose: verbose)
        end
        
        results[:gems] = ensure_gems(verbose: verbose)
        results[:repos] = ensure_repos(verbose: verbose)
        
        results
      end
      
      # Install missing OpenBSD packages
      def ensure_packages(packages: OPENBSD_PACKAGES, verbose: true)
        return [] unless openbsd?
        
        installed = []
        packages.each do |pkg|
          next if package_installed?(pkg)
          
          puts "Installing package: #{pkg}" if verbose
          if install_package(pkg)
            installed << pkg
          else
            warn "Failed to install: #{pkg}" if verbose
          end
        end
        installed
      end
      
      # Install missing Ruby gems
      def ensure_gems(gems: GEMS, verbose: true)
        installed = []
        gems.each do |gem_name|
          next if gem_installed?(gem_name)
          
          puts "Installing gem: #{gem_name}" if verbose
          if install_gem(gem_name)
            installed << gem_name
          else
            warn "Failed to install gem: #{gem_name}" if verbose
          end
        end
        installed
      end
      
      # Clone missing GitHub repos
      def ensure_repos(repos: REPOS, dir: REPOS_DIR, verbose: true)
        FileUtils.mkdir_p(dir)
        
        cloned = []
        repos.each do |repo, desc|
          repo_name = repo.split('/').last
          target = File.join(dir, repo_name)
          
          next if File.directory?(target)
          
          puts "Cloning #{repo} (#{desc})" if verbose
          if clone_repo(repo, target)
            cloned << repo
          else
            warn "Failed to clone: #{repo}" if verbose
          end
        end
        cloned
      end
      
      # Check if specific package is installed
      def package_installed?(name)
        return false unless openbsd?
        system("pkg_info -e '#{name}-*' > /dev/null 2>&1")
      end
      
      # Check if specific gem is installed
      def gem_installed?(name)
        Gem::Specification.find_by_name(name)
        true
      rescue Gem::MissingSpecError
        false
      end
      
      # Check if repo is cloned
      def repo_cloned?(repo, dir: REPOS_DIR)
        repo_name = repo.split('/').last
        File.directory?(File.join(dir, repo_name))
      end
      
      # Install OpenBSD package
      def install_package(name)
        return false unless openbsd?
        system("doas pkg_add -I #{name} > /dev/null 2>&1")
      end
      
      # Install Ruby gem
      def install_gem(name)
        system("gem install #{name} --no-document > /dev/null 2>&1")
      end
      
      # Clone GitHub repo
      def clone_repo(repo, target)
        system("git clone --depth 1 https://github.com/#{repo}.git #{target} > /dev/null 2>&1")
      end
      
      # List missing dependencies
      def missing
        {
          packages: openbsd? ? OPENBSD_PACKAGES.reject { |p| package_installed?(p) } : [],
          gems: GEMS.reject { |g| gem_installed?(g) },
          repos: REPOS.keys.reject { |r| repo_cloned?(r) }
        }
      end
      
      # Summary of what's installed
      def status
        {
          packages: openbsd? ? OPENBSD_PACKAGES.select { |p| package_installed?(p) } : [],
          gems: GEMS.select { |g| gem_installed?(g) },
          repos: REPOS.keys.select { |r| repo_cloned?(r) }
        }
      end
      
      private
      
      def openbsd?
        RUBY_PLATFORM.include?('openbsd')
      end
    end
    
    # Shell environment setup
    ZSHRC_LINES = [
      'export MASTER_TTY_INPUT=1',
      'export EDITOR=vim'
    ].freeze
    
    class << self
      # Ensure .zshrc has MASTER settings
      def setup_shell(verbose: true)
        zshrc = File.expand_path('~/.zshrc')
        return [] unless File.exist?(zshrc)
        
        content = File.read(zshrc)
        added = []
        
        ZSHRC_LINES.each do |line|
          next if content.include?(line)
          File.open(zshrc, 'a') { |f| f.puts line }
          added << line
          puts "Added to .zshrc: #{line}" if verbose
        end
        
        added
      end
    end
  end
end
