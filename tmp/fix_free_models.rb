# encoding: utf-8
# frozen_string_literal: true
BASE = "/home/dev/pub4/MASTER"

# Create a monkey-patch initializer that teaches RubyLLM about :free models
# by registering them in its model catalog on boot.
init_path = File.join(BASE, "lib/master/ruby_llm_patch.rb")

patch = <<~'PATCH'
# frozen_string_literal: true

# Monkey-patch RubyLLM to handle OpenRouter :free model variants.
# RubyLLM's internal catalog doesn't know about :free suffixed models.
# This patch makes unknown models pass through as-is rather than raising.

module RubyLLM
  class Models
    alias_method :original_find, :find

    def find(model_id)
      original_find(model_id)
    rescue ModelNotFoundError
      # For OpenRouter :free models and other unknown models,
      # create a minimal model entry so the request goes through.
      id = model_id.to_s
      provider = if id.include?("/")
                   "openrouter"
                 else
                   "openai"
                 end
      Model.new(
        id: id,
        name: id,
        provider: provider,
        type: "chat",
        context_window: 128_000,
        max_tokens: 4096,
        supports_vision: false,
        supports_functions: true,
        supports_structured_output: false,
        input_price_per_million: 0.0,
        output_price_per_million: 0.0,
        metadata: {},
        slug: id,
        family: id.split("/").first
      )
    end
  end
end
PATCH

File.write(init_path, patch)
puts "created: lib/master/ruby_llm_patch.rb"

# Require the patch early in master.rb
master_path = File.join(BASE, "lib/master.rb")
content = File.read(master_path, encoding: "utf-8")
unless content.include?("ruby_llm_patch")
  # Add after the require "ruby_llm" line or at the top
  if content.include?('require "ruby_llm"')
    content.sub!('require "ruby_llm"', "require \"ruby_llm\"\nrequire_relative \"master/ruby_llm_patch\"")
  else
    # Find where RubyLLM is first used and add before
    content.sub!("module Master", "require_relative \"master/ruby_llm_patch\"\n\nmodule Master")
  end
  File.write(master_path, content)
  puts "master.rb: loads ruby_llm_patch"
end

puts "done"
