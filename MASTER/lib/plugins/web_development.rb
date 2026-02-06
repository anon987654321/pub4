# frozen_string_literal: true

require 'yaml'

module MASTER
  module Plugins
    class WebDevelopment
      @config = nil
      @config_mtime = nil
      @enabled = false

      class << self
        def config
          load_config unless @config
          @config
        end

        def load_config
          path = config_path
          return @config = default_config unless File.exist?(path)

          current_mtime = File.mtime(path)
          if @config && @config_mtime == current_mtime
            return @config
          end

          @config = YAML.load_file(path, symbolize_names: true)
          @config_mtime = current_mtime
          @config
        rescue => e
          warn "Failed to load web development config: #{e.message}"
          @config = default_config
        end

        def config_path
          File.join(__dir__, '..', 'config', 'plugins', 'web_development.yml')
        end

        def default_config
          {
            enabled: false,
            rails: { version: '7.0', api_mode: false, turbo: true, stimulus: true },
            frontend: { framework: 'vanilla', build_tool: 'esbuild', css_framework: 'tailwind' },
            responsive: { breakpoints: { mobile: 320, tablet: 768, desktop: 1024, wide: 1440 } },
            pwa: { enabled: false, offline: true, installable: true },
            performance: { lazy_load: true, code_splitting: true, compression: true, caching: true },
            seo: { meta_tags: true, sitemap: true, robots: true, structured_data: true },
            security: { csp: true, cors: true, https_only: true, rate_limiting: true }
          }
        end

        def enabled?
          @enabled
        end

        def enable
          @enabled = true
          load_config
          validate
        end

        def disable
          @enabled = false
        end

        def configure(options = {})
          load_config
          @config = @config.merge(options)
          validate
        end

        def apply(context = {})
          return { success: false, error: 'Plugin not enabled' } unless enabled?

          results = []
          
          # Apply Rails configuration
          if config[:rails]
            results << apply_rails(context)
          end

          # Apply frontend configuration
          if config[:frontend]
            results << apply_frontend(context)
          end

          # Apply responsive design
          if config[:responsive]
            results << apply_responsive(context)
          end

          # Apply PWA features
          if config[:pwa] && config[:pwa][:enabled]
            results << apply_pwa(context)
          end

          # Apply performance optimizations
          if config[:performance]
            results << apply_performance(context)
          end

          # Apply SEO optimizations
          if config[:seo]
            results << apply_seo(context)
          end

          # Apply security features
          if config[:security]
            results << apply_security(context)
          end

          {
            success: true,
            applied: results.compact,
            timestamp: Time.now
          }
        rescue => e
          { success: false, error: e.message }
        end

        def validate
          errors = []
          errors.concat(validate_rails)
          errors.concat(validate_frontend)
          errors.concat(validate_responsive)
          errors << 'PWA config must be a hash' if config[:pwa] && !config[:pwa].is_a?(Hash)
          errors << 'Performance config must be a hash' if config[:performance] && !config[:performance].is_a?(Hash)
          errors << 'SEO config must be a hash' if config[:seo] && !config[:seo].is_a?(Hash)
          errors << 'Security config must be a hash' if config[:security] && !config[:security].is_a?(Hash)
          errors.any? ? { valid: false, errors: errors } : { valid: true }
        end

        def validate_rails
          return [] unless config[:rails]
          return ['Rails config must be a hash'] unless config[:rails].is_a?(Hash)
          
          version = config[:rails][:version]
          version && !version.to_s.match?(/^\d+\.\d+/) ? ['Invalid Rails version format'] : []
        end

        def validate_frontend
          return [] unless config[:frontend]
          return ['Frontend config must be a hash'] unless config[:frontend].is_a?(Hash)
          
          framework = config[:frontend][:framework]
          return [] unless framework
          
          valid = %w[vanilla react vue svelte alpine]
          valid.include?(framework.to_s) ? [] : ["Invalid framework: #{framework}"]
        end

        def validate_responsive
          return [] unless config[:responsive]
          return ['Responsive config must be a hash'] unless config[:responsive].is_a?(Hash)
          
          bp = config[:responsive][:breakpoints]
          return [] unless bp
          return ['Breakpoints must be a hash'] unless bp.is_a?(Hash)
          
          bp.filter_map do |name, value|
            "Invalid breakpoint #{name}: #{value}" unless value.is_a?(Numeric) && value > 0
          end
        end

        private :validate_rails, :validate_frontend, :validate_responsive

        def rails_config
          config[:rails] || {}
        end

        def generate_rails_app(options = {})
          rails_opts = rails_config.merge(options)
          
          cmd_parts = ['rails', 'new', options[:name] || 'app']
          cmd_parts << '--api' if rails_opts[:api_mode]
          cmd_parts << '--skip-turbo' unless rails_opts[:turbo]
          cmd_parts << '--skip-stimulus' unless rails_opts[:stimulus]
          
          cmd_parts.join(' ')
        end

        def frontend_config
          config[:frontend] || {}
        end

        def generate_frontend_setup
          frontend = frontend_config
          
          {
            framework: frontend[:framework],
            build_tool: frontend[:build_tool],
            css_framework: frontend[:css_framework],
            setup_commands: frontend_setup_commands
          }
        end

        def responsive_config
          config[:responsive] || {}
        end

        def breakpoint(name)
          responsive_config.dig(:breakpoints, name.to_sym)
        end

        def media_query(name)
          bp = breakpoint(name)
          bp ? "@media (min-width: #{bp}px)" : nil
        end

        def pwa_config
          config[:pwa] || {}
        end

        def generate_manifest
          return nil unless pwa_config[:enabled]
          
          {
            name: 'Application',
            short_name: 'App',
            start_url: '/',
            display: 'standalone',
            background_color: '#ffffff',
            theme_color: '#000000',
            icons: []
          }
        end

        def generate_service_worker
          return nil unless pwa_config[:enabled]
          
          features = []
          features << 'offline_support' if pwa_config[:offline]
          features << 'installable' if pwa_config[:installable]
          
          { enabled: true, features: features }
        end

        def performance_config
          config[:performance] || {}
        end

        def performance_recommendations
          recommendations = []
          perf = performance_config
          
          recommendations << 'Enable lazy loading' if perf[:lazy_load]
          recommendations << 'Implement code splitting' if perf[:code_splitting]
          recommendations << 'Enable compression' if perf[:compression]
          recommendations << 'Configure caching' if perf[:caching]
          
          recommendations
        end

        def seo_config
          config[:seo] || {}
        end

        def generate_meta_tags(page_data = {})
          return nil unless seo_config[:meta_tags]
          
          {
            title: page_data[:title] || 'Application',
            description: page_data[:description] || '',
            keywords: page_data[:keywords] || [],
            og_tags: {
              'og:title': page_data[:title],
              'og:description': page_data[:description],
              'og:type': 'website'
            }
          }
        end

        def security_config
          config[:security] || {}
        end

        def generate_security_headers
          return nil unless security_config
          
          headers = {}
          sec = security_config
          
          if sec[:csp]
            headers['Content-Security-Policy'] = "default-src 'self'"
          end
          
          if sec[:https_only]
            headers['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains'
          end
          
          if sec[:cors]
            headers['Access-Control-Allow-Origin'] = '*'
          end
          
          headers
        end

        private

        def apply_rails(context)
          {
            type: 'rails',
            data: rails_config,
            setup_command: generate_rails_app(context),
            applied_to: context[:target] || 'application'
          }
        end

        def apply_frontend(context)
          {
            type: 'frontend',
            data: frontend_config,
            setup: generate_frontend_setup,
            applied_to: context[:target] || 'application'
          }
        end

        def apply_responsive(context)
          {
            type: 'responsive',
            data: responsive_config,
            media_queries: responsive_config[:breakpoints]&.keys&.map { |bp| media_query(bp) },
            applied_to: context[:target] || 'styles'
          }
        end

        def apply_pwa(context)
          {
            type: 'pwa',
            data: pwa_config,
            manifest: generate_manifest,
            service_worker: generate_service_worker,
            applied_to: context[:target] || 'application'
          }
        end

        def apply_performance(context)
          {
            type: 'performance',
            data: performance_config,
            recommendations: performance_recommendations,
            applied_to: context[:target] || 'application'
          }
        end

        def apply_seo(context)
          {
            type: 'seo',
            data: seo_config,
            meta_tags: generate_meta_tags(context[:page_data]),
            applied_to: context[:target] || 'pages'
          }
        end

        def apply_security(context)
          {
            type: 'security',
            data: security_config,
            headers: generate_security_headers,
            applied_to: context[:target] || 'application'
          }
        end

        def frontend_setup_commands
          framework = frontend_config[:framework]
          build_tool = frontend_config[:build_tool]
          
          commands = []
          
          case framework
          when 'react'
            commands << 'npm install react react-dom'
          when 'vue'
            commands << 'npm install vue'
          when 'svelte'
            commands << 'npm install svelte'
          when 'alpine'
            commands << 'npm install alpinejs'
          end
          
          case build_tool
          when 'esbuild'
            commands << 'npm install esbuild --save-dev'
          when 'webpack'
            commands << 'npm install webpack webpack-cli --save-dev'
          when 'vite'
            commands << 'npm install vite --save-dev'
          end
          
          commands
        end
      end
    end
  end
end
