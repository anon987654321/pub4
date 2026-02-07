# frozen_string_literal: true

require "json"

module MASTER
  module DB
    module Queries
      def self.extended(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Axioms
        def axioms(category: nil, protection: nil)
          query = "SELECT * FROM axioms"
          conditions, params = [], []

          if category
            conditions << "category = ?"
            params << category
          end
          if protection
            conditions << "protection = ?"
            params << protection
          end

          query += " WHERE #{conditions.join(' AND ')}" if conditions.any?
          query += " ORDER BY CASE protection WHEN 'ABSOLUTE' THEN 1 WHEN 'PROTECTED' THEN 2 ELSE 3 END"
          connection.execute(query, params)
        end

        # Council
        def council(veto_only: false)
          query = "SELECT * FROM council"
          query += " WHERE veto = 1" if veto_only
          query += " ORDER BY weight DESC"
          connection.execute(query)
        end

        def council_personas
          connection.execute("SELECT * FROM council ORDER BY weight DESC")
        end

        def get_persona(name)
          connection.execute("SELECT * FROM council WHERE slug = ?", [name]).first
        end

        # Config
        def config(key)
          row = connection.execute("SELECT value FROM config WHERE key = ?", [key]).first
          row ? row["value"] : nil
        end

        def set_config(key, value)
          connection.execute("INSERT OR REPLACE INTO config (key, value) VALUES (?, ?)", [key, value])
        end

        # Costs
        def log_cost(model:, tokens_in:, tokens_out:, cost:)
          synchronize do
            connection.execute(
              "INSERT INTO costs (model, tokens_in, tokens_out, cost) VALUES (?, ?, ?, ?)",
              [model, tokens_in, tokens_out, cost]
            )
          end
        end

        def total_cost
          result = connection.execute("SELECT SUM(cost) as total FROM costs").first
          result["total"].to_f
        end

        # Circuit breaker
        def circuit(model)
          connection.execute("SELECT * FROM circuits WHERE model = ?", [model]).first
        end

        def trip!(model)
          synchronize do
            connection.execute(
              "INSERT INTO circuits (model, failures, last_failure, state) VALUES (?, 1, datetime('now'), 'open')
               ON CONFLICT(model) DO UPDATE SET failures = failures + 1, last_failure = datetime('now'), state = 'open'",
              [model]
            )
          end
        end

        def reset!(model)
          synchronize do
            connection.execute(
              "INSERT INTO circuits (model, failures, state) VALUES (?, 0, 'closed')
               ON CONFLICT(model) DO UPDATE SET failures = 0, state = 'closed'",
              [model]
            )
          end
        end

        # Agents
        def record_agent(agent)
          task_json = JSON.generate(agent.task) rescue "{}"
          result_json = agent.result ? JSON.generate(agent.result.ok? ? agent.result.value : { error: agent.result.error }) : "{}"

          connection.execute(
            "INSERT OR REPLACE INTO agents (id, parent_id, scope, status, task_json, result_json, budget, user_agent, finished_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))",
            [agent.id, agent.parent_id, agent.scope, agent.status.to_s, task_json, result_json, agent.budget, agent.user_agent]
          )
          update_reputation(agent)
        end

        def update_reputation(agent)
          scope = agent.scope
          connection.execute("INSERT OR IGNORE INTO agent_reputation (agent_scope) VALUES (?)", [scope])
          connection.execute("UPDATE agent_reputation SET total_runs = total_runs + 1 WHERE agent_scope = ?", [scope])

          case agent.status
          when :completed
            connection.execute("UPDATE agent_reputation SET successful = successful + 1 WHERE agent_scope = ?", [scope])
          when :timeout
            connection.execute("UPDATE agent_reputation SET timeouts = timeouts + 1 WHERE agent_scope = ?", [scope])
          when :failed
            connection.execute("UPDATE agent_reputation SET rejected = rejected + 1 WHERE agent_scope = ?", [scope])
          end
        end

        def agent_reputation(scope)
          connection.execute("SELECT * FROM agent_reputation WHERE agent_scope = ?", [scope]).first
        end

        def agents(parent_id: nil)
          if parent_id
            connection.execute("SELECT * FROM agents WHERE parent_id = ?", [parent_id])
          else
            connection.execute("SELECT * FROM agents")
          end
        end
      end
    end

    extend Queries::ClassMethods
  end
end
