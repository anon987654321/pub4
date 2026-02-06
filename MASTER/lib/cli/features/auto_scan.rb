# frozen_string_literal: true

module MASTER
  class CLI
    module Features
      module AutoScan
        # Auto-scan on boot feature
        
        def auto_scan_on_boot
          return if @auto_scan_disabled
          return unless should_auto_scan?
          
          # Use constants from the including class
          c_dim = self.class.const_get(:C_DIM)
          c_reset = self.class.const_get(:C_RESET)
          icon_ok = self.class.const_get(:ICON_OK)
          
          puts "#{c_dim}Auto-scanning project...#{c_reset}"
          
          begin
            result = scan_path('.')
            @last_scan_time = Time.now
            puts "#{c_dim}#{icon_ok} Scan complete#{c_reset}"
          rescue => e
            puts "#{c_dim}Auto-scan failed: #{e.message}#{c_reset}"
          end
        end
        
        def should_auto_scan?
          # Don't auto-scan if scanned recently
          return false if @last_scan_time && (Time.now - @last_scan_time) < 3600
          
          # Don't auto-scan in large repos
          file_count = Dir.glob(File.join(@root, '**', '*.rb')).count
          return false if file_count > 500
          
          # Auto-scan if no prior scan
          !@last_scan_time
        end
        
        def disable_auto_scan
          @auto_scan_disabled = true
          "Auto-scan disabled"
        end
        
        def enable_auto_scan
          @auto_scan_disabled = false
          "Auto-scan enabled"
        end
      end
    end
  end
end
