# frozen_string_literal: true

module Shared
  module Commerce
    # PermissionGraph — governs the economic access layer.
    # It tracks which entities (users, apps, partners) have permissions for specific commerce actions.
    class PermissionGraph
      # Maps a subject (entity) to their permitted actions on a resource.
      # Example: { "user_123" => { "product_456" => [:view, :buy, :promote] } }
      attr_reader :graph

      def initialize(graph = {})
        @graph = graph
      end

      def permit?(subject, action, resource)
        permissions = graph.dig(subject, resource)
        return false unless permissions
        
        permissions.include?(action)
      end

      def grant(subject, action, resource)
        @graph[subject] ||= {}
        @graph[subject][resource] ||= []
        @graph[subject][resource] << action unless @graph[subject][resource].include?(action)
      end

      def revoke(subject, action, resource)
        return unless @graph.dig(subject, resource)
        @graph[subject][resource].delete(action)
      end

      def permissions_for(subject, resource)
        @graph.dig(subject, resource) || []
      end
    end
  end
end
