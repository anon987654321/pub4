# frozen_string_literal: true

module MASTER
  # OpenBSD pledge and unveil integration for enhanced security
  class OpenBSDPledge
    # Standard pledge promises for different modes
    PROMISES = {
      minimal: 'stdio',
      read_only: 'stdio rpath',
      network: 'stdio rpath wpath cpath inet dns',
      full: 'stdio rpath wpath cpath inet dns proc exec'
    }.freeze
    
    # Unveil paths for file system access
    UNVEIL_PATHS = {
      lib: { path: '/home/runner/work/pub4/pub4/lib', permissions: 'r' },
      var: { path: '/home/runner/work/pub4/pub4/var', permissions: 'rwc' },
      tmp: { path: '/tmp', permissions: 'rwc' },
      home: { path: ENV['HOME'], permissions: 'rwc' }
    }.freeze
    
    class << self
      # Apply pledge with given promises
      def pledge(mode = :network)
        return unless openbsd?
        
        promises = PROMISES[mode] || mode.to_s
        
        begin
          # On OpenBSD, would call: pledge(promises, nil)
          # For now, just log what we would do
          log_security_action("Would pledge: #{promises}")
          true
        rescue => e
          warn "Pledge failed: #{e.message}"
          false
        end
      end
      
      # Unveil filesystem paths
      def unveil(paths = UNVEIL_PATHS)
        return unless openbsd?
        
        paths.each do |name, config|
          path = config[:path]
          perms = config[:permissions]
          
          begin
            # On OpenBSD, would call: unveil(path, perms)
            log_security_action("Would unveil: #{path} (#{perms})")
          rescue => e
            warn "Unveil failed for #{path}: #{e.message}"
          end
        end
        
        # Lock unveil (no more paths can be unveiled)
        begin
          # On OpenBSD, would call: unveil(nil, nil)
          log_security_action("Would lock unveil")
          true
        rescue => e
          warn "Unveil lock failed: #{e.message}"
          false
        end
      end
      
      # Apply both pledge and unveil
      def secure(mode = :network, paths = UNVEIL_PATHS)
        unveil(paths) && pledge(mode)
      end
      
      # Check if running on OpenBSD
      def openbsd?
        RUBY_PLATFORM =~ /openbsd/
      end
      
      # Get current security status
      def status
        {
          platform: RUBY_PLATFORM,
          openbsd: openbsd?,
          pledge_available: openbsd?,
          unveil_available: openbsd?,
          current_mode: @current_mode || :none
        }
      end
      
      # Recommended security profile for CLI
      def cli_profile
        paths = {
          lib: UNVEIL_PATHS[:lib],
          var: UNVEIL_PATHS[:var],
          tmp: UNVEIL_PATHS[:tmp]
        }
        
        secure(:network, paths)
        @current_mode = :cli
      end
      
      # Recommended security profile for server
      def server_profile
        paths = {
          lib: UNVEIL_PATHS[:lib],
          var: UNVEIL_PATHS[:var],
          tmp: UNVEIL_PATHS[:tmp]
        }
        
        secure(:network, paths)
        @current_mode = :server
      end
      
      # Minimal security profile for read-only operations
      def readonly_profile
        paths = {
          lib: UNVEIL_PATHS[:lib]
        }
        
        secure(:read_only, paths)
        @current_mode = :readonly
      end
      
      private
      
      # Log security actions
      def log_security_action(message)
        return unless ENV['DEBUG'] || ENV['SECURITY_LOG']
        
        timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
        puts "[SECURITY #{timestamp}] #{message}"
      end
    end
  end
end
