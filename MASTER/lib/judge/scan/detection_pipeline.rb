# frozen_string_literal: true
module Master
  module Judge
    module Scan
      class DetectionPipeline
        def initialize(definition, agent: nil, root: nil)
          @def = definition
          @agent = agent
        end

        def run(ctx)
          findings = []
          file_type = guess_medium(ctx[:file_path])
          @def.adapters.each do |adapter|
            next unless adapter["medium"] == file_type || adapter["medium"] == "any"
            detection = adapter["detection"]
            if detection["lexical"]
              findings.concat(run_lexical(detection["lexical"], ctx))
            elsif detection["structural"]
              findings.concat(run_structural(detection["structural"], ctx))
            elsif detection["semantic"] && @agent
              findings.concat(run_semantic(detection["semantic"], ctx))
            end
          end
          findings
        end

        private

        def guess_medium(path)
          ext = File.extname(path.to_s).downcase
          return "ruby" if ext == ".rb"
          return "javascript" if [".js", ".ts"].include?(ext)
          return "html" if [".html", ".erb"].include?(ext)
          "any"
        end

        def run_lexical(cfg, ctx)
          findings = []
          cfg.each do |scope, conf|
            next unless conf["pattern"]
            pattern = Regexp.new(conf["pattern"])
            if scope == "file_line" && ctx[:file_content]
              ctx[:file_content].each_line.with_index(1) do |line, num|
                if line =~ pattern
                  findings << finding(num, conf["message"] || @def.description)
                end
              end
            end
          end
          findings
        end

        def run_structural(cfg, ctx)
          findings = []
          cfg.each do |scope, conf|
            next unless conf["matcher"]
            case conf["matcher"]
            when "cyclomatic_complexity"
              cc = calculate_cc(ctx[:file_content])
              if cc && cc > conf["threshold"].to_i
                findings << finding(1, "Cyclomatic complexity #{cc} exceeds #{conf["threshold"]}")
              end
            when "method_length"
              max_len = max_method_length(ctx[:file_content])
              if max_len && max_len > conf["threshold"].to_i
                findings << finding(1, "Method has #{max_len} lines (max #{conf["threshold"]})")
              end
            when "nesting_depth"
              depth = max_nesting(ctx[:file_content])
              if depth && depth > conf["threshold"].to_i
                findings << finding(1, "Nesting depth #{depth} exceeds #{conf["threshold"]}")
              end
            end
          end
          findings
        end

        def run_semantic(cfg, ctx)
          findings = []
          cfg.each do |scope, conf|
            next unless conf["prompt"]
            prompt = conf["prompt"]
            response = @agent.ask(prompt, context: ctx[:file_content][0, 3000])
            if response && response.strip.upcase != "CLEAN"
              findings << finding(1, response.to_s[0, 200])
            end
          end
          findings
        end

        def finding(line, message)
          { rule: @def.id, message: message, line: line, severity: @def.severity }
        end

        CC_NODES = %w[
          IfNode UnlessNode WhileNode UntilNode ForNode
          CaseNode WhenNode RescueNode AndNode OrNode
        ].map { |n| "Prism::#{n}" }.to_set.freeze

        def calculate_cc(code)
          result = Prism.parse(code)
          return nil if result.failure?
          count = 1
          result.value.breadth_first_search { |node|
            count += 1 if CC_NODES.include?(node.class.name)
            false
          }
          count
        rescue StandardError => _e
          nil
        end

        def max_method_length(code)
          result = Prism.parse(code)
          return nil if result.failure?
          max = 0
          result.value.breadth_first_search { |node|
            if node.is_a?(Prism::DefNode)
              len = node.location.end_line - node.location.start_line
              max = len if len > max
            end
            false
          }
          max.zero? ? nil : max
        rescue StandardError => _e
          nil
        end

        def max_nesting(code)
          result = Prism.parse(code)
          return nil if result.failure?
          max_depth(result.value, 0)
        rescue StandardError => _e
          nil
        end

        NESTING_NODES = [
          Prism::ModuleNode, Prism::ClassNode, Prism::DefNode,
          Prism::IfNode, Prism::WhileNode, Prism::CaseNode
        ].freeze

        def max_depth(node, depth)
          return depth unless node.respond_to?(:child_nodes)
          child_depth = NESTING_NODES.include?(node.class) ? depth + 1 : depth
          children = node.child_nodes
          children.compact.reduce(child_depth) { |m, c| [m, max_depth(c, child_depth)].max }
        end
      end
    end
  end
end
