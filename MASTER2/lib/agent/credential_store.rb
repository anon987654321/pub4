# frozen_string_literal: true

module MASTER
  class AgentFirewall
    # CredentialStore -- domain-pinned secrets
    # Inspired by OpenClaw PR #23110 credential firewall pattern (gistfile10)
    # A credential registered for api.openai.com CANNOT be used for any other domain.
    module CredentialStore
      module_function

      @store = {}
      @store_mutex = Mutex.new

      # Register a named credential pinned to specific domains.
      # @param name [Symbol, String] credential identifier
      # @param secret [String] the secret value
      # @param domains [Array<String>, String] authorized domains
      def register(name, secret:, domains:)
        @store_mutex.synchronize do
          @store[name.to_sym] = {
            secret: secret,
            domains: Set.new(Array(domains)),
            created: Time.now,
            last_used: nil,
            use_count: 0,
          }
        end
        Logging.dmesg_log("cred0", message: "action=registered name=#{name} domains=#{Array(domains).join(',')}")
        Result.ok
      end

      # Fetch a credential, enforcing domain pinning.
      # @param name [Symbol, String] credential identifier
      # @param for_domain [String] the domain this credential will be used with
      # @return [Result] ok with secret: or err if not authorized
      def fetch(name, for_domain:)
        @store_mutex.synchronize do
          entry = @store[name.to_sym]
          return Result.err("Unknown credential: #{name}") unless entry

          unless entry[:domains].include?(for_domain)
            Logging.dmesg_log("cred0",
                              message: "action=BLOCKED name=#{name} requested_domain=#{for_domain} pinned=#{entry[:domains].to_a.join(',')}")
            return Result.err("Credential '#{name}' not authorized for domain '#{for_domain}'")
          end

          entry[:last_used] = Time.now
          entry[:use_count] += 1
          Result.ok(secret: entry[:secret])
        end
      end

      # Return audit log of all registered credentials (no secrets).
      def audit_log
        @store_mutex.synchronize do
          @store.map do |k, v|
            { name: k, domains: v[:domains].to_a, uses: v[:use_count], last_used: v[:last_used] }
          end
        end
      end
    end
  end
end
