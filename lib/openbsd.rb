# frozen_string_literal: true
require "net/http"
require "uri"
require "fileutils"

module MASTER
  module OpenBSD
    # Pledge/Unveil support for security sandboxing
    class << self
      def pledge(promises, execpromises = nil)
        return false unless openbsd?
        # Ruby doesn't have native pledge - would need FFI
        # For now, document intent
        @pledged = promises
        true
      end

      def unveil(path, permissions)
        return false unless openbsd?
        @unveiled ||= []
        @unveiled << { path: path, permissions: permissions }
        true
      end

      def openbsd?
        RUBY_PLATFORM.include?('openbsd')
      end

      def sandbox_status
        return 'not openbsd' unless openbsd?
        pledged = @pledged || 'none'
        unveiled = @unveiled&.size || 0
        "pledge: #{pledged}, unveil: #{unveiled} paths"
      end
    end

    CONFIG_MAP = {
      "pf.conf" => { daemon: "pf", man: "pf.conf.5", path: "/etc/pf.conf" },
      "httpd.conf" => { daemon: "httpd", man: "httpd.conf.5", path: "/etc/httpd.conf" },
      "smtpd.conf" => { daemon: "smtpd", man: "smtpd.conf.5", path: "/etc/mail/smtpd.conf" },
      "nsd.conf" => { daemon: "nsd", man: "nsd.conf.5", path: "/var/nsd/etc/nsd.conf" },
      "relayd.conf" => { daemon: "relayd", man: "relayd.conf.5", path: "/etc/relayd.conf" },
      "acme-client.conf" => { daemon: "acme-client", man: "acme-client.conf.5", path: "/etc/acme-client.conf" },
      "doas.conf" => { daemon: "doas", man: "doas.conf.5", path: "/etc/doas.conf" },
      "sshd_config" => { daemon: "sshd", man: "sshd_config.5", path: "/etc/ssh/sshd_config" },
      "login.conf" => { daemon: "login", man: "login.conf.5", path: "/etc/login.conf" },
      "ntpd.conf" => { daemon: "ntpd", man: "ntpd.conf.5", path: "/etc/ntpd.conf" }
    }.freeze

    MAN_BASE_URL = "https://man.openbsd.org"
    CACHE_TTL = 86400  # 24 hours

    class << self
      def extract_configs(code)
        configs = []
        CONFIG_MAP.each do |name, meta|
          # Match heredoc patterns: cat > /path <<'EOF' or cat > /path << EOF
          pattern = /cat\s*>\s*#{Regexp.escape(meta[:path])}\s*<<'?(\w+)'?\n(.*?)\n\1/m
          code.scan(pattern) do |_, content|
            configs << {
              name: name,
              path: meta[:path],
              daemon: meta[:daemon],
              man_page: meta[:man],
              content: content.strip
            }
          end
        end
        configs
      end

      def fetch_man_page(man_page, cache_dir = nil)
        cache_dir ||= File.join(Master::ROOT, "var", "cache", "man")
        FileUtils.mkdir_p(cache_dir) rescue nil
        
        cache_file = File.join(cache_dir, man_page.gsub("/", "_"))
        
        # Check cache
        if File.exist?(cache_file)
          age = Time.now.to_i - File.mtime(cache_file).to_i
          return File.read(cache_file) if age < CACHE_TTL
        end
        
        # Fetch from man.openbsd.org
        uri = URI("#{MAN_BASE_URL}/#{man_page}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 30
        
        resp = http.get(uri.path)
        return nil unless resp.code == "200"
        
        content = resp.body
        File.write(cache_file, content) rescue nil
        content
      rescue => e
        nil
      end

      def validate_config(name, content)
        warnings = []
        meta = CONFIG_MAP[name]
        return { valid: true, warnings: [] } unless meta

        case name
        when "pf.conf"
          warnings << "Missing 'block' default policy" unless content.include?("block")
          warnings << "No 'pass' rules defined" unless content.include?("pass")
        when "httpd.conf"
          warnings << "No 'server' block defined" unless content.include?("server")
          warnings << "Missing 'listen on'" unless content.include?("listen on")
        when "smtpd.conf"
          warnings << "No 'listen on' directive" unless content.include?("listen on")
          warnings << "No 'action' defined" unless content.include?("action")
        when "nsd.conf"
          warnings << "Missing 'server:' block" unless content.include?("server:")
          warnings << "Missing 'zone:' (nsd requires zone definitions)" unless content.include?("zone:")
        when "acme-client.conf"
          warnings << "Missing 'authority' block" unless content.include?("authority")
          warnings << "Missing 'domain' (acme-client needs domain)" unless content.include?("domain")
        when "relayd.conf"
          warnings << "No 'relay' or 'redirect' defined" unless content =~ /relay|redirect/
        when "doas.conf"
          warnings << "No 'permit' rules" unless content.include?("permit")
        end

        { valid: warnings.empty?, warnings: warnings }
      end

      def analyze_shell_file(file_path, llm)
        code = File.read(file_path, encoding: "UTF-8")
        configs = extract_configs(code)
        
        return [] if configs.empty?

        results = []
        configs.each_with_index do |cfg, idx|
          puts "conf#{idx}: #{cfg[:name]} at #{cfg[:path]} (#{cfg[:content].lines.size} lines)"
          puts "  daemon: #{cfg[:daemon]}, man: #{cfg[:man_page]}"
          
          man_content = fetch_man_page(cfg[:man_page])
          if man_content
            puts "  man0: fetched #{MAN_BASE_URL}/#{cfg[:man_page]} (#{man_content.size} bytes)"
          end
          
          validation = validate_config(cfg[:name], cfg[:content])
          if validation[:warnings].any?
            validation[:warnings].each_with_index do |w, wi|
              puts "  warn#{wi}: #{w}"
            end
            results << { config: cfg, warnings: validation[:warnings], man: man_content }
          else
            puts "  valid: no issues"
          end
        end
        
        results
      end
    end
  end
end
