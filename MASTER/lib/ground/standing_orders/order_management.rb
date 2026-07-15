# frozen_string_literal: true

module Master
  module Ground
    class StandingOrders
      # CRUD + display for the order definitions themselves — separate from
      # StandingOrders' own scheduling/event-dispatch responsibility.
      module OrderManagement
        def upsert(name:, description: "", trigger: "scheduled",
                   interval_s: 86_400, command:, enabled: true)
          existing = @orders.find { |o| o["name"] == name.to_s }
          if existing
            existing.merge!(
              "description" => description, "trigger" => trigger.to_s,
              "interval_s" => interval_s.to_i, "command" => command.to_s, "enabled" => enabled
            )
          else
            @orders << {
              "name" => name.to_s, "description" => description.to_s, "trigger" => trigger.to_s,
              "interval_s" => interval_s.to_i, "command" => command.to_s, "enabled" => enabled,
              "state" => "pending", "last_run_at" => 0
            }
          end
          persist
          "standing order '#{name}' saved"
        end

        def enable(name)  = toggle(name, true)
        def disable(name) = toggle(name, false)

        def reset(name)
          order = @orders.find { |x| x["name"] == name.to_s }
          return "no order named '#{name}'" unless order
          order["state"] = "pending"
          order.delete("last_error")
          persist
          "'#{name}' reset -> pending"
        end

        def list
          return "no standing orders defined" if @orders.empty?
          @orders.map { |o| format_order(o) }.join("\n")
        end

        def format_order(o)
          st = state_of(o)
          flag = o["enabled"] ? "on" : "off"
          last = o["last_run_at"].to_i > 0 ? Time.at(o["last_run_at"].to_i).strftime("%Y-%m-%d") : "never"
          err = o["last_error"] ? "  !! #{o["last_error"][0, 60]}" : ""
          "#{o['name']} [#{flag}|#{st}] - #{o['description']} (last: #{last})#{err}"
        end
      end
    end
  end
end
