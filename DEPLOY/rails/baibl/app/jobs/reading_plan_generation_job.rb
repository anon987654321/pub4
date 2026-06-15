# frozen_string_literal: true

class ReadingPlanGenerationJob < ApplicationJob
  queue_as :default

  def perform(plan_id)
    plan = ReadingPlan.find(plan_id)
    books = Book.ordered.limit(plan.duration_days)
    books.each_with_index do |book, i|
      plan.reading_plan_days.find_or_create_by!(day_number: i + 1) do |day|
        day.book = book
        day.chapter_start = 1
        day.chapter_end = [book.chapters.count, 1].max
      end
    end

    Shared::EventEmitter.call("baibl.reading_plan.generated", plan_id: plan.id) if defined?(Shared::EventEmitter)
  end
end