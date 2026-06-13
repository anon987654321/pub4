# frozen_string_literal: true

require "open3"
require "shellwords"
require "fileutils"

module Master
  module Now
    module CommandRegistry
      module_function

      def tool_commands(root, ai = nil)
        agent = ai && ai[:agent]
        {
          "postpro" => ->(ctx) { dispatch_master_tool(root:, tool: "postpro", arg: arg_for(ctx)) },
          "repligen" => ->(ctx) { dispatch_master_tool(root:, tool: "repligen", arg: arg_for(ctx)) },
          "photograph" => ->(ctx) { dispatch_photograph(root:, agent: agent, ctx: ctx) },

          "sing" => ->(ctx) { dispatch_sing(root:, ctx: ctx) },
        }
      end

      def dispatch_master_tool(root:, tool:, arg:)
        script = File.join(root, "tools", "#{tool}.rb")
        return "#{tool}: missing tool entrypoint #{script}" unless File.file?(script)

        argv = Shellwords.split(arg.to_s)
        out, status = Open3.capture2e(RbConfig.ruby, script, *argv, chdir: File.expand_path("..", root))
        status.success? ? out.strip : "#{tool}: exit=#{status.exitstatus}\n#{out.strip}"
      rescue ArgumentError => e
        "#{tool}: bad arguments: #{e.message}"
      rescue StandardError => e
        "#{tool}: #{e.class}: #{e.message}"
      end

      def dispatch_photograph(root:, agent:, ctx:)
        prompt = arg_for(ctx).to_s.strip
        return "usage: /photograph <prompt>   (attach photo token for ref vision analysis)" if prompt.empty?

        image = ctx[:image] if ctx.respond_to?(:[]) && ctx.key?(:image)
        model = "black-forest-labs/flux-1.1-pro"

        refined_prompt = prompt
        if image && agent
          # Use free vision model (gemini-2.0-flash-exp:free via routing) for ref analysis + prompt refine.
          # Leverages the image attachment wiring (path or data).
          vision_prompt = "You are an expert photography prompt engineer. Given the user request and attached reference image (if present), output ONE highly detailed photorealistic prompt optimized for Flux. Include subject details, lighting, composition, camera, film stock emulation intent (e.g. kodak portra), mood, depth of field. Output ONLY the prompt text, no quotes or explanation."
          begin
            refined = agent.ask(vision_prompt, image: image)
            refined_prompt = refined.to_s.strip.lines.first(3).join(" ").strip if refined
            refined_prompt = prompt if refined_prompt.empty? || refined_prompt.length < 20
          rescue StandardError => e
            refined_prompt = prompt
          end
        end

        # Generate using repligen (reuses our generate support + predict + download to output/ dir)
        gen_arg = "#{model} #{refined_prompt}"
        gen_out = dispatch_master_tool(root: root, tool: "repligen", arg: "generate #{gen_arg}")

        # Parse output dir from the generate print ( "Output: output/..." )
        output_dir = gen_out[ /Output: (output\/[^\s]+)/ , 1 ] || Dir.glob("output/*").max { |a,b| File.mtime(a) <=> File.mtime(b) }

        unless output_dir && Dir.exist?(output_dir)
          return "photograph: generate failed or no output dir\n#{gen_out}"

        # Postpro the generated images for genuinely good film photography look (kodak_portra portrait)
        # Process files in the dir using postpro script per file (supports --input file --output ...)
        processed_dir = "#{output_dir}_postpro"
        FileUtils.mkdir_p(processed_dir) rescue nil

        images = Dir.glob(File.join(output_dir, "*.{jpg,jpeg,png,webp}")).sort
        results = []
        images.each do |img|
          base = File.basename(img, ".*")
          outf = File.join(processed_dir, "#{base}.jpg")
          p_arg = "--input #{img} --output #{outf} --preset portrait --stock kodak_portra"
          p_out = dispatch_master_tool(root: root, tool: "postpro", arg: p_arg)
          results << (File.exist?(outf) ? outf : p_out)
        end

        [
          "photograph: vision=#{!!image} model=#{model}",
          "refined: #{refined_prompt[0,120]}...",
          "generated: #{output_dir}",
          "postpro (#{results.size} files): #{processed_dir}",
          results.join("\n"),
        ].join("\n")
def dispatch_sing(root:, ctx:)
  prompt = arg_for(ctx).to_s.strip
  return "usage: /sing <lyrics or singing prompt>   (Replicate suno-ai/bark)" if prompt.empty?
end

      end
    end
  end
end
