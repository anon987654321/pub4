# frozen_string_literal: true

namespace :dintero do
  desc "Register the configured marketplace webhook subscription with Dintero"
  task "hooks:create" => :environment do
    abort "Dintero hooks are not configured" unless Marketplace::Payments::DinteroHooks.configured?

    response = Marketplace::Payments::DinteroHooks.create!
    puts JSON.pretty_generate(response)
  end

  desc "List configured Dintero marketplace webhook subscriptions"
  task "hooks:list" => :environment do
    abort "Dintero hooks are not configured" unless Marketplace::Payments::DinteroHooks.configured?

    response = Marketplace::Payments::DinteroHooks.list
    puts JSON.pretty_generate(response)
  end
end
