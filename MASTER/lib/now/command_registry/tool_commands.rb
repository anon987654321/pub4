# frozen_string_literal: true

require "fileutils"

module Master
  module Now
    module CommandRegistry
      module_function

      def tool_commands(root, ai = nil)
        agent = ai && ai[:agent]
        {
          "postpro" => command(:dispatch_postpro, root),
          "repligen" => command(:dispatch_repligen, root, agent),
          "photograph" => command(:dispatch_photograph, root, agent),
          "prompt" => command(:dispatch_prompt, root, agent),
        }
      end

      def dispatch_postpro(root, ctx: nil)
        dispatch_master_tool(root:, tool: "postpro", arg: arg_for(ctx))
      end

      def dispatch_repligen(root, agent, ctx: nil)
        arg = arg_for(ctx).to_s.strip
        arg = Reach::RepligenArg.refine_generate(arg, agent: agent, ctx: ctx) if agent
        dispatch_master_tool(root:, tool: "repligen", arg: arg)
      end

      def dispatch_master_tool(root:, tool:, arg:)
        Reach::ScriptDispatch.run_string(root:, tool:, arg:)
      end

      def dispatch_photograph(root, agent, ctx: nil)
        prompt = arg_for(ctx).to_s.strip
        return "usage: /photograph <seed>   (LLM expands + Strunk-polishes; attach photo for ref)" if prompt.empty?

        image = Reach::RepligenArg.ctx_image(ctx)
        model = "black-forest-labs/flux-1.1-pro"
        refined_prompt = refine_generation_prompt(prompt, medium: :photo, agent: agent, image: image)

        gen_arg = "#{model} #{refined_prompt}"
        gen_out = dispatch_master_tool(root: root, tool: "repligen", arg: "generate #{gen_arg}")

        output_dir = gen_out[/Output: (output\/[^\s]+)/, 1] || Dir.glob("output/*").max { |a, b| File.mtime(a) <=> File.mtime(b) }

        unless output_dir && Dir.exist?(output_dir)
          return "photograph: generate failed or no output dir\n#{gen_out}"
        end

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
          "refined: #{refined_prompt[0, 120]}...",
          "generated: #{output_dir}",
          "postpro (#{results.size} files): #{processed_dir}",
          results.join("\n"),
        ].join("\n")
      end

      def dispatch_prompt(root, agent, ctx: nil)
        args = arg_for(ctx).to_s.strip
        return prompt_usage if args.empty?

        medium = :photo
        seed = args
        if args =~ /\A(photo|video)\s+(.+)/i
          medium = $1.downcase == "video" ? :video : :photo
          seed = $2.strip
        end
        return prompt_usage if seed.empty?

        image = Reach::RepligenArg.ctx_image(ctx)
        refined = refine_generation_prompt(seed, medium: medium, agent: agent, image: image)
        [
          "prompt: medium=#{medium}",
          "seed: #{seed}",
          "refined: #{refined}",
        ].join("\n")
      end

      def prompt_usage
        "usage: /prompt <seed>   or   /prompt photo <seed>   /prompt video <seed>"
      end

      def refine_generation_prompt(prompt, medium:, agent:, image: nil)
        Master::Reach::GenerationPromptRefiner.refine(
          prompt: prompt,
          medium: medium,
          agent: agent,
          image: image
        )
      end
    end
  end
end