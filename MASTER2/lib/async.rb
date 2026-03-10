# frozen_string_literal: true

def Async
  task = Object.new
  def task.with_timeout(_secs)
    yield
  end
  yield(task)
end
