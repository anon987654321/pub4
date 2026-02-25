# frozen_string_literal: true

module MASTER
  # GroundedContext -- injects MASTER2's own source + gem READMEs into the LLM
  # system message so the model reasons from real code, not hallucinated APIs.
  #
  # Depth levels:
  #   :shallow   -- current default: system_prompt.yml + dir tree only
  #   :own        -- MASTER2 lib/ key files + data/ YAMLs + LLM.md  (selfrun default)
  #   :deep       -- :own + gem READMEs from Gemfile dependencies
  #   :full       -- :deep + complete gem source (expensive; 1M+ ctx models only)
  #
  # Token budget is enforced: files are prioritised then truncated to fit.
  # Encoding: ~4 chars per token (conservative estimate).
  module GroundedContext
    CHARS_PER_TOKEN  = 4
    GEMS_BUNDLE_PATH = "var/bundle/ruby"
    BUDGETS = {
      shallow: 0,
      own:     60_000 * CHARS_PER_TOKEN,  # ~60k tokens
      deep:    120_000 * CHARS_PER_TOKEN, # ~120k tokens
      full:    400_000 * CHARS_PER_TOKEN, # ~400k tokens -- kimi/gemini only
    }.freeze

    # Files loaded first (highest signal for self-analysis)
    OWN_PRIORITY = %w[
      LLM.md
      data/constitution.yml
      data/axioms.yml
      data/detectors.yml
      data/design.yml
      data/models.yml
      data/council.yml
      data/system_prompt.yml
      lib/result.rb
      lib/llm.rb
      lib/pipeline.rb
      lib/executor.rb
      lib/executor/context.rb
      lib/executor/tools.rb
      lib/chamber/review.rb
      lib/review/enforcer.rb
      lib/enforcement/layers.rb
      lib/db_jsonl.rb
      lib/boot.rb
      bin/master
    ].freeze

    module_function

    # Build grounded source section for system message injection.
    # Returns a string ready to append to ExecutionContext.build_system_message.
    def build(depth: :own, root: MASTER.root)
      return "" if depth == :shallow

      budget = BUDGETS[depth] || BUDGETS[:own]
      sections = []
      used = 0

      # Own source files -- priority list first, then remaining lib/
      own_files = priority_files(root) + remaining_lib_files(root)
      own_files.uniq.each do |rel|
        break if used >= budget

        path = File.join(root, rel)
        next unless File.file?(path)

        content = safe_read(path, budget - used)
        next if content.empty?

        sections << "### #{rel}\n```\n#{content}\n```"
        used += content.length
      end

      # Gem READMEs for :deep and :full
      if depth == :deep || depth == :full
        gem_readmes(root).each do |name, text|
          break if used >= budget

          chunk = text[0, [budget - used, 3000].min]
          next if chunk.empty?

          sections << "### gem: #{name} (README)\n#{chunk}"
          used += chunk.length
        end
      end

      # Full gem source for :full only
      if depth == :full
        gem_sources(root).each do |rel, content|
          break if used >= budget

          chunk = content[0, budget - used]
          next if chunk.empty?

          sections << "### gem src: #{rel}\n```ruby\n#{chunk}\n```"
          used += chunk.length
        end
      end

      return "" if sections.empty?

      tokens_used = (used / CHARS_PER_TOKEN).round
      header = "GROUNDED SOURCE CONTEXT (#{tokens_used}k tokens, depth: #{depth}):\n" \
               "The following is the actual MASTER2 source. Reason from this, not memory.\n"
      header + sections.join("\n\n")
    rescue StandardError => err
      Logging.warn("grounded_context: #{err.message}") if defined?(Logging)
      ""
    end

    def priority_files(root)
      OWN_PRIORITY.select { |f| File.file?(File.join(root, f)) }
    end

    def remaining_lib_files(root)
      lib = File.join(root, "lib")
      return [] unless Dir.exist?(lib)

      Dir.glob("#{lib}/**/*.rb")
        .map { |f| f.sub("#{root}/", "") }
        .reject { |f| OWN_PRIORITY.include?(f) }
        .sort_by { |f| File.size(File.join(root, f)) }  # smaller files first
    end

    def gem_readmes(root)
      gems_dir = File.join(root, GEMS_BUNDLE_PATH)
      readmes = {}
      return readmes unless Dir.exist?(gems_dir)

      Dir.glob("#{gems_dir}/**/gems/*/README*").each do |path|
        name = path.split("/gems/").last.split("/").first
        readmes[name] ||= File.read(path)[0, 4000]
      rescue StandardError
        next
      end
      readmes
    end

    def gem_sources(root)
      gems_dir = File.join(root, GEMS_BUNDLE_PATH)
      sources = {}
      return sources unless Dir.exist?(gems_dir)

      Dir.glob("#{gems_dir}/**/gems/*/lib/**/*.rb").each do |path|
        rel = path.sub("#{root}/", "")
        sources[rel] = File.read(path)
      rescue StandardError
        next
      end
      sources
    end

    def safe_read(path, budget)
      content = File.read(path)
      # Truncate to budget with notice
      if content.length > budget
        cut = content[0, budget]
        # Don't cut mid-line
        cut = cut[0, cut.rindex("\n") || budget]
        "#{cut}\n# ... [truncated: #{content.length - cut.length} chars omitted]"
      else
        content
      end
    rescue StandardError
      ""
    end
  end
end
