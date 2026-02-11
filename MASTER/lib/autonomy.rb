module MASTER
  class Autonomy
    def decide(action, risk, context = {})
      case risk
      when 'low'
        :apply
      when 'medium'
        context[:user_confirm] ? :apply : :preview
      when 'high'
        :ask
      end
    end

    def converge(consecutive_no_changes)
      consecutive_no_changes > 3 ? :converged : :continue
    end
  end
end
