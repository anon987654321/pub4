# frozen_string_literal: true

# Likes, reactions and follows arrive one person at a time, and in the grouped
# inbox ten likes on one post read as ten rows saying the same thing. They are
# folded per target: "Kari og 3 andre likte innlegget ditt", with the single
# rows behind a disclosure so each can still be read or dismissed. A follow's
# target is always the reader, so all follows on a page fold into one.
module NotificationClustersHelper
  FOLDED_KINDS = %w[like reaction follow].freeze

  # items is one kind's notifications, newest first; so is each cluster.
  def notification_clusters(kind, items)
    return items.map { [ _1 ] } unless FOLDED_KINDS.include?(kind.to_s)

    follows = kind.to_s == "follow"
    items.group_by { |notification| follows ? :reader : [ notification.notifiable_type, notification.notifiable_id ] }
         .values
  end

  # A lone notification is its own card; several are one folded card.
  def notification_cluster_card(cluster)
    return render("notifications/notification", notification: cluster.first) if cluster.one?

    render("notifications/cluster", cluster:)
  end

  def notification_cluster_headline(cluster)
    newest = cluster.first
    name = newest.shown_actor&.display_name || t("notifications.aggregate.someone")
    kind = newest.kind.to_s
    key = kind == "follow" ? "follow" : "#{kind}_#{newest.notifiable_type == "Post" ? "post" : "other"}"
    t("notifications.aggregate.#{key}", name:, count: cluster.size - 1)
  end
end
