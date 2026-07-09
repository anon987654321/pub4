# frozen_string_literal: true

namespace :vapid do
  desc "Generate VAPID keys — add output to .env or credentials"
  task generate: :environment do
    key = Webpush.generate_key
    puts "VAPID_PUBLIC_KEY=#{key.public_key}"
    puts "VAPID_PRIVATE_KEY=#{key.private_key}"
    puts "VAPID_SUBJECT=mailto:admin@brgen.no"
  end
end
