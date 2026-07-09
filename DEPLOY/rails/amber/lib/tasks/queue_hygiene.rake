# frozen_string_literal: true

namespace :amber do
  namespace :queue do
    desc "Report pending Solid Queue jobs by class"
    task report: :environment do
      rows = SolidQueue::Job.where(finished_at: nil).group(:class_name).count.sort_by { |_, c| -c }
      puts "pending=#{rows.sum(&:last)}"
      rows.first(20).each { |klass, count| puts format("%5d  %s", count, klass) }
    end

    desc "Purge finished jobs and collapse duplicate bulk wardrobe/media jobs"
    task sweep: :environment do
      cleared = SolidQueue::Job.clear_finished_in_batches(sleep_between_batches: 0.2)
      puts "cleared_finished=#{cleared}"

      %w[WardrobeMediaJob Shared::MediaProcessingJob].each do |klass|
        dupes = SolidQueue::Job.where(finished_at: nil, class_name: klass)
          .order(:id).pluck(:id, :arguments)
        seen = {}
        removed = 0
        dupes.each do |id, args|
          key = args.to_s
          if seen[key]
            SolidQueue::Job.where(id: id).delete_all
            removed += 1
          else
            seen[key] = true
          end
        end
        puts "deduped #{klass}: #{removed}" if removed.positive?
      end
    end
  end
end