# frozen_string_literal: true

# ErrorInterceptor - Captures system command errors and attempts self-healing
module MASTER
  module ErrorInterceptor
    # Execute a system command safely with error interception
    # Returns [output, exit_code]
    def system_safe(cmd)
      out = `#{cmd} 2>&1`
      code = $?.exitstatus
      
      if code != 0
        fixes = SelfHealing.fix(cmd, out, code)
        fixes&.each { |f| system(f) }
      end
      
      [out, code]
    end
  end
end
