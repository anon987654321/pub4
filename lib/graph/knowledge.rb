# frozen_string_literal: true
require "json"

module Master
  module Graph
    class Knowledge
      attr_reader :nodes, :edges
      
      def initialize
        @nodes = []
        @edges = []
        @node_ids = Set.new
      end
      
      # Add a file node
      def add_file_node(path, violations: [], score: 100)
        node_id = "file:#{path}"
        return if @node_ids.include?(node_id)
        
        @nodes << {
          id: node_id,
          type: "file",
          label: File.basename(path),
          path: path,
          violations: violations.size,
          score: score,
          size: File.exist?(path) ? File.size(path) : 0
        }
        @node_ids.add(node_id)
      end
      
      # Add a principle node
      def add_principle_node(principle, violation_count: 0, tier: "axiom", priority: 8)
        node_id = "principle:#{principle}"
        return if @node_ids.include?(node_id)
        
        @nodes << {
          id: node_id,
          type: "principle",
          label: principle,
          tier: tier,
          priority: priority,
          violation_count: violation_count
        }
        @node_ids.add(node_id)
      end
      
      # Add a smell node
      def add_smell_node(smell)
        node_id = "smell:#{smell}"
        return if @node_ids.include?(node_id)
        
        @nodes << {
          id: node_id,
          type: "smell",
          label: smell
        }
        @node_ids.add(node_id)
      end
      
      # Add an edge (relationship)
      def add_edge(from, to, type:, severity: "medium")
        @edges << {
          from: from,
          to: to,
          type: type,
          severity: severity
        }
      end
      
      # Build graph from analysis results
      def build_from_analysis(results)
        # Process each file's analysis
        results.each do |file, data|
          violations = data[:violations] || []
          score = data[:score] || 100
          
          add_file_node(file, violations: violations, score: score)
          
          # Add violation relationships
          violations.each do |violation|
            principle = violation[:principle] || violation["principle"]
            next unless principle
            
            add_principle_node(principle)
            add_edge(
              "file:#{file}",
              "principle:#{principle}",
              type: "violates",
              severity: violation[:severity] || "medium"
            )
            
            # Add smell if present
            if violation[:smell]
              smell = violation[:smell]
              add_smell_node(smell)
              add_edge("file:#{file}", "smell:#{smell}", type: "has_smell")
            end
          end
        end
        
        self
      end
      
      # Calculate graph metrics
      def calculate_metrics
        {
          total_nodes: @nodes.size,
          total_edges: @edges.size,
          files: @nodes.count { |n| n[:type] == "file" },
          principles: @nodes.count { |n| n[:type] == "principle" },
          smells: @nodes.count { |n| n[:type] == "smell" },
          avg_violations_per_file: average_violations_per_file,
          most_violated_principle: most_violated_principle,
          worst_files: worst_files(5)
        }
      end
      
      # Export to JSON
      def to_json(*args)
        {
          nodes: @nodes,
          edges: @edges,
          metrics: calculate_metrics
        }.to_json(*args)
      end
      
      # Export to hash
      def to_h
        {
          nodes: @nodes,
          edges: @edges,
          metrics: calculate_metrics
        }
      end
      
      # Generate D3.js compatible format
      def to_d3_format
        {
          nodes: @nodes.map { |n| n.merge(id: n[:id]) },
          links: @edges.map do |e|
            {
              source: e[:from],
              target: e[:to],
              type: e[:type],
              severity: e[:severity]
            }
          end
        }
      end
      
      private
      
      def average_violations_per_file
        file_nodes = @nodes.select { |n| n[:type] == "file" }
        return 0 if file_nodes.empty?
        
        total = file_nodes.sum { |n| n[:violations] }
        (total.to_f / file_nodes.size).round(2)
      end
      
      def most_violated_principle
        principle_nodes = @nodes.select { |n| n[:type] == "principle" }
        return nil if principle_nodes.empty?
        
        principle_nodes.max_by { |n| n[:violation_count] }&.fetch(:label)
      end
      
      def worst_files(limit)
        @nodes.select { |n| n[:type] == "file" }
              .sort_by { |n| -n[:violations] }
              .take(limit)
              .map { |n| { path: n[:path], violations: n[:violations], score: n[:score] } }
      end
    end
  end
end
