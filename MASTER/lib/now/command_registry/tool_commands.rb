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
          "postpro" => command(:dispatch_postpro, root),
          "repligen" => command(:dispatch_repligen, root),
          "photograph" => command(:dispatch_photograph, root, agent),
          "video" => command(:dispatch_video, root, agent),
          "prompt" => command(:dispatch_prompt, root, agent),
        }
      end

      def dispatch_postpro(root, ctx: nil)
        dispatch_master_tool(root:, tool: "postpro", arg: arg_for(ctx))
      end

      def dispatch_repligen(root, ctx: nil)
        dispatch_master_tool(root:, tool: "repligen", arg: arg_for(ctx))
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

      def dispatch_photograph(root, agent, ctx: nil)
        prompt = arg_for(ctx).to_s.strip
        return "usage: /photograph <seed>   (LLM expands + Strunk-polishes; attach photo for ref)" if prompt.empty?

        image = ctx[:image] if ctx.respond_to?(:[]) && ctx.key?(:image)
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

      DEFAULT_VIDEO_MODEL = "minimax/video-01-live"

      def dispatch_video(root, agent, ctx: nil)
        prompt = arg_for(ctx).to_s.strip
        return "usage: /video <seed>   (LLM expands + Strunk-polishes → #{DEFAULT_VIDEO_MODEL})" if prompt.empty?

        image = ctx[:image] if ctx.respond_to?(:[]) && ctx.key?(:image)
        refined_prompt = refine_generation_prompt(prompt, medium: :video, agent: agent, image: image)

        gen_out = dispatch_master_tool(
          root: root,
          tool: "repligen",
          arg: "generate #{DEFAULT_VIDEO_MODEL} #{refined_prompt}"
        )

        output_dir = gen_out[/Output: (output\/[^\s]+)/, 1]
        videos = output_dir ? Dir.glob(File.join(output_dir, "*.{mp4,webm,mov,gif}")).sort : []

        [
          "video: model=#{DEFAULT_VIDEO_MODEL}",
          "seed: #{prompt[0, 80]}#{"..." if prompt.length > 80}",
          "refined: #{refined_prompt[0, 160]}#{"..." if refined_prompt.length > 160}",
          (videos.any? ? "files: #{videos.join(", ")}" : gen_out),
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

        image = ctx[:image] if ctx.respond_to?(:[]) && ctx.key?(:image)
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

      def arg_for(ctx) = ctx.to_h.fetch(:args, "").to_s.strip
    end
  end
end
