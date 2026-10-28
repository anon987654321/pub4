# frozen_string_literal: true

require_relative "route_policy"

module Master
  module CLI
    module Routing
      class ModelRouter
        # Selection orchestration; reachability, health, and compute remain
        # replaceable collaborators owned by the existing router.
        module Selection
          def preferred(task_type: :exploration)
            return @config.model unless enabled?
            return preferred_local(task_type:) if local_only?

            empirical_best = @capability_map.best_model_for(task_type)
            candidates = reachable_candidates(task_type)
            return live_config_model(task_type:) if candidates.empty?

            ids = healthy(candidates).filter_map { |model| model["id"] }
            ids = floor_candidates(candidates, operation: task_type).filter_map { |model| model["id"] } if ids.empty?
            @compute_pool.select(Io::LaneSelection.best_class(ids, free_last: !free_route?(task_type)), task_type:, empirical_best:) ||
              ids.first ||
              live_config_model(task_type:)
          end

          # Only reachable, non-silent lanes enter the chain. Empirical health and
          # cost ranking order candidates within the final policy: premium/API,
          # free API, browser chat, then local compute. Local availability is not
          # an offline contract.
          def fallback_chain(task_type: :exploration)
            return [@config.model] unless enabled?

            candidates = Routing::RoutePolicy.normalize(chain_for(task_type))
            reachable = candidates.select { |id| reachable?(id) }
            # Parked apart from unusable: a silent or spent lane stays a candidate when
            # nothing is usable, so the dispatcher can name why; a parked model does not.
            parked = reachable.reject { |id| Io::LaneState.usable?(id, sources: %i[parked]) }
            unparked = reachable.reject { |id| parked.include?(id) }

            recently_failed = unparked.select { |id| recently_failed?(id) }
            answering = unparked.reject { |id| recently_failed.include?(id) }
            needs_floor = answering.empty?
            meets_floor = needs_floor ? unparked.select { |id| @availability.meets_floor?(id, operation: task_type) } : []
            local = needs_floor ? meets_floor.select { |id| @availability.level_for(id) == "L2" } : []

            usable = unparked.select { |id| Io::LaneState.usable?(id) }

            decision = Routing::RoutePolicy.call(
              candidates:, reachable:, parked:, usable:, recently_failed:, meets_floor:, local:,
            )

            ranked = @provider_health.rank(decision.selected)
            ranked = @compute_pool.rank(ranked, task_type:)
            selected = chitchat_head(
              Io::LaneSelection.order_or_all(
                ranked,
                free_last: !free_route?(task_type),
                latency: method(:latency_s),
                lead: Io::LaneSelection.route_lead(@rules, task_type),
              ),
              task_type,
            )
            priority_fallback_order(selected)
          end

          # Greetings are explicitly routed to the free tier. A locally installed
          # subscription CLI used to jump ahead of `pref`, contradicting the route
          # table and spending the strongest lane on “hello”. Keep it available as
          # fallback, but let the task-specific preference lead.
          # Seconds a model took when it last answered, nil when never measured.
          def latency_s(model_id) = (@compute_pool.latency_s(model_id) if @compute_pool.respond_to?(:latency_s))

          def chain_for(task_type)
            return local_only_chain(task_type:) if local_only?

            lanes = { pref: [preferred(task_type:)], tiers: tier_ids.reject { |id| ollama_model?(id) },
                      free: continuity_models + hosted_models + browser_chat_models + local_server_models,
                      subscription: agy_catalog_models + Ground::AuthProfileLane.models_for_router(self) + primary_models + cli_lane_models }
            order = task_type.to_sym == :chitchat ? %i[pref tiers free subscription] : %i[subscription pref tiers free]
            order.flat_map { |lane| lanes.fetch(lane) } + Io::PaidTail.models + replicate_models + local_models + [@config.model]
          end

          def constrained_for(operation:)
            return preferred_local(task_type: operation) if local_only?

            constraint = @rules.dig("operation_constraints", operation.to_s)
            return preferred(task_type: operation) unless constraint

            min_quality = constraint.fetch("min_quality", 0.0).to_f
            preferred_tier = constraint.fetch("preferred_tier", "strong")
            candidates = @rules.dig("models", preferred_tier).to_a
            qualified = healthy(candidates).select { |m| m.dig("score", "quality").to_f >= min_quality }
            return preferred(task_type: operation) if qualified.empty?

            ids = Io::LaneSelection.best_class(qualified.filter_map { |m| m["id"] })
            @compute_pool.select(ids, task_type: operation) || preferred(task_type: operation)
          end

          # The pool ranks the whole chain by measured utility, and on a machine
          # with a subscription CLI that put the strongest lane ahead of the free
          # tier for "hello", which chain_for exists to prevent. For chitchat the
          # free and keyless lanes stay in front, in the pool's order.
          # The terminal fallback order is independent of preference/ranking:
          # premium and paid API lanes first, free API lanes next, browser chat next,
          # and local compute last. A preferred local model must never jump the queue.
          # Public: Review::Agent::ModelSelector reorders a biased chain with it.
          def priority_fallback_order(models)
            Array(models).map(&:to_s).reject(&:empty?).uniq.each_with_index.sort_by do |model, index|
              rank = if web_chat_model?(model)
                       3
                     elsif free_api_model?(model)
                       2
                     else
                       case Io::LaneSelection.kind(model)
                       when :local then 4
                       when :paid_tail then 1
                       else 0
                       end
                     end
              [rank, index]
            end.map(&:first)
          end

          private

          def free_api_model?(model)
            return true if model.to_s.end_with?(":free", ":cloud", "-cloud")
            return false unless hosted_model?(model)

            endpoint = hosted_endpoint_for(model)
            endpoint && endpoint.fetch(:key, nil).nil?
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "model_router.free_api_model", model:)
            false
          end

          def chitchat_head(chain, task_type)
            return chain unless task_type.to_sym == :chitchat

            head = Array(@rules.dig("models", "free")).filter_map { |row| row["id"] } +
                   Array(@rules.dig("openrouter", "free_latest"))
            chain.partition { |id| head.include?(id) }.flatten
          end

          def enabled?
            @rules.dig("routing", "enabled") != false
          end

          # Greetings and explanations are routed to the free tier on purpose;
          # every other route keeps free models last.
          def free_route?(task_type) = @rules.dig("routes", task_type.to_s) == "free"

          def reachable_candidates(task_type)
            tier = @rules.dig("routes", task_type.to_s) || @rules.dig("routes", "fallback_default") || "cheap"
            @rules.dig("models", tier).to_a.select { |model| reachable?(model["id"]) }
          end

          def healthy(models)
            # unhealthy? already includes recent failures; don't read provider health twice.
            models.reject { |m| unhealthy?(m["id"]) || !reachable?(m["id"]) }
          end

          def floor_candidates(models, operation:)
            models.select do |model|
              id = model["id"]
              @availability.meets_floor?(id, operation:) &&
                !unhealthy?(id)
            end
          end

          def live_config_model(task_type:)
            id = @config.model.to_s
            if !id.empty? && !unhealthy?(id) && reachable?(id)
              return id
            end

            ids = tier_ids.select do |candidate|
              !unhealthy?(candidate) &&
                reachable?(candidate) &&
                @availability.meets_floor?(candidate, operation: task_type)
            end
            ids.first
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "model_router.live_config_model", model: id)
            nil
          end

          # Excluded only while a failure is the newest thing known about the lane.
          # This used to exclude every lane whose last answer was older than the
          # freshness window, success or not, so an idle lane was never asked and
          # stayed stale: on 2026-10-26 opus, 8 answers and no failure, sat out a
          # whole /fix while free models read the tree.
          def recently_failed?(model_id)
            level = @availability.level_for(model_id)
            return false if level == "L2"

            @provider_health.recently_failed?(model_id, max_age_s: @availability.health_freshness_s)
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "ModelRouter.recently_failed?", model: model_id)
            false
          end

          def effective_score(model)
            weighted_score(model["score"] || {}) * health_score(model["id"])
          end

          def health_score(model_id)
            @provider_health ? @provider_health.score(model_id) : 1.0
          rescue StandardError
            1.0
          end

          def unhealthy?(model_id)
            quota = begin
              Io::ModelQuota.forecast(model_id)
            rescue StandardError => e
              # A corrupt/unreadable free-model quota ledger must not make the
              # quota-tracked lane look healthy. ModelQuota returns nil without
              # I/O for non-free lanes, so this only parks a candidate whose
              # budget could not be established.
              Master::Ground::Swallow.log(e, context: "ModelRouter.quota", model: model_id, severity: :load_bearing)
              return Io::ModelQuota.trackable?(model_id)
            end
            return true if quota && quota[:remaining].zero?
            return true if quota && quota[:projected_daily] >= quota[:limit] * 0.8
            # llm_dispatcher.rb writes every failed call here regardless of which
            # path selected the model, but constrained_for (scan_semantic,
            # council, code_generation, ...) only ever consulted @provider_health,
            # which nothing in this codebase constructs — it is always nil. A
            # model that just failed kept winning the same weighted comparison on
            # the very next file, forever, since it never saw its own failure.
            return true unless Io::LaneState.usable?(model_id)
            @provider_health.unhealthy?(model_id) || recently_failed?(model_id)
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "ModelRouter.unhealthy?")
            false
          end

          def weighted_score(score)
            weights = @rules.fetch("weights", {})
            qw = [weights.fetch("quality", 1.0).to_f, 0.01].max
            sw = [weights.fetch("speed", 1.0).to_f, 0.01].max
            cw = [weights.fetch("cost", 1.0).to_f, 0.01].max
            q = score.fetch("quality", 0.5).to_f * qw
            s = [score.fetch("speed", 1.0).to_f * sw, 0.01].max
            c = [score.fetch("cost", 0.5).to_f * cw, 0.001].max
            q * s * c
          end

          def local_only?
            ENV["MASTER_LOCAL_ONLY"] == "1"
          end

          def local_only_chain(task_type:)
            candidates = local_candidates
            ids = candidates.select { |id| reachable?(id) && !unhealthy?(id) }
            selected = @compute_pool.rank(ids, task_type:)
            selected.empty? ? ids : selected
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "model_router.local_only_chain")
            []
          end

          def local_candidates
            (Array(local_models) + Array(local_server_models)).map(&:to_s).reject(&:empty?).uniq
          end

          def preferred_local(task_type:)
            ids = local_only_chain(task_type:)
            return ids.first if ids.any?

            @config.model.to_s if @config.model.to_s.match?(/\A(?:ollama:|ollama\/|local:)/)
          end
        end
      end
    end
  end
end
