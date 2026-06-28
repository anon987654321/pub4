# frozen_string_literal: true

module Master
  module Now
    module CommandRegistry
      module_function

      def domain_commands(root:)
        {
          "domain" => command(:dispatch_domain, root),
        }
      end

      def dispatch_domain(root, ctx: nil)
        args = arg_for(ctx).to_s.strip.downcase
        domain = args.empty? ? "brgen" : args.split(/\s+/, 2).first
        tool = Master::Reach::SubdomainOrchestrator.new(root: root)
        result = tool.call(domain: domain, context: args)
        return result.message unless result.ok?

        payload = result.value!
        JSON.pretty_generate(payload)
      end
    end
  end
end