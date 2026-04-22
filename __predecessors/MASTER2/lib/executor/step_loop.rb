# frozen_string_literal: true

module MASTER
  class Executor
    # StepLoop - shared step-iteration logic for ReAct, PreAct, ReWOO, Reflexion.
    # Each strategy includes this module and calls run_step_loop, yielding a block
    # that returns either :continue (keep looping) or a Result (done / error).
    module StepLoop
      # Run up to max_steps iterations, yielding (step_num, plan) each time.
      # The block must return:
      #   :continue     -- proceed to next step
      #   Result        -- finished (ok or err); immediately returned to caller
      #
      # Returns Result.err when the wall-clock timeout fires or max_steps is hit.
      def run_step_loop(goal, max_steps)
        start_time = MASTER::Utils.monotonic_now
        plan       = Plan.new

        max_steps.times do |i|
          step_num = i + 1

          # Timeout guard -- check_timeout! raises Result::Error (defined in
          # MASTER::Result::Error < StandardError) which we convert to Result.err.
          if (err = timeout_error_for(start_time))
            return err
          end

          step_result = yield step_num, plan

          case step_result
          when :continue
            next
          when Result
            return step_result
          else
            return Result.err("StepLoop: unexpected block return value: #{step_result.inspect}")
          end
        end

        Result.err("Max steps (#{max_steps}) reached without completion for goal: #{goal.to_s.slice(0, 80)}")
      end

      private

      # Converts check_timeout!'s raise into a returnable Result so strategy
      # step loops can use a single-line guard instead of a 4-line begin/rescue.
      # Result::Error is defined in lib/result.rb as class Error < StandardError.
      def timeout_error_for(start_time)
        check_timeout!(start_time)
        nil
      rescue Result::Error => err
        Result.err(err.message, category: :timeout)
      end
    end
  end
end
