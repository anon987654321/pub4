# frozen_string_literal: true

require 'logger'
require 'sqlite3'
require 'mail'
require 'concurrent-ruby'
require 'net/http'
require_relative '../lib/scraper'

# Main class for managing apartment hunting
class ApartmentHunter
  TARGET_URL = 'https://www.finn.no/realestate/lettings/search.html'
  NOTIFICATION_INTERVAL = 3600 # Notification interval in seconds

  def initialize(api_key)
    @api_key = api_key
    @scraper = Scraper.new(@api_key, TARGET_URL)
    @logger = Logger.new('apartment_hunter.log')
    @user_webhook_url = nil # Optional: Set this if using webhooks for notification
    setup_mailer
    setup_database
    define_search_criteria
  end

  def define_search_criteria
    @search_criteria = {
      city: 'Bergen',
      max_price: 9000,
      min_size: 20,
      animals: true,
      occupants: 2,
      newly_refurbished: true,
      city_center: true,
      seaside: false,
      outskirts: false,
      family: false
    }
  end

  def setup_mailer
    settings = {
      address: 'localhost',
      port: 25,
      enable_starttls_auto: false
    }
    Mailer.setup(settings)
  end

  def setup_database
    @db = SQLite3::Database.new 'listings.db'
    @db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS listings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        url TEXT UNIQUE,
        seen BOOLEAN NOT NULL DEFAULT FALSE
      );
    SQL
  end

  def monitor_listings
    @logger.info('Starting to monitor listings...')
    while keep_monitoring?
      perform_listing_checks
      sleep NOTIFICATION_INTERVAL
    end
    @logger.info('Monitoring stopped.')
  end

  def keep_monitoring?
    true
  end

  def perform_listing_checks
    Concurrent::Future.execute { process_listings }
  end

  def process_listings
    listings = @scraper.fetch_listings
    listings.each do |listing|
      next if listing_seen?(listing[:url])

      mark_listing_as_seen(listing[:url])
      notify_user_of_listing(listing) if meets_criteria?(listing)
    end
  end

  def listing_seen?(url)
    result = @db.execute('SELECT seen FROM listings WHERE url = ?', [url])
    !result.empty? && result.first['seen'] == 1
  end

  def mark_listing_as_seen(url)
    @db.execute('INSERT OR IGNORE INTO listings (url, seen) VALUES (?, TRUE)', [url])
  end

  def meets_criteria?(listing)
    @search_criteria.all? { |key, value| listing[key] == value }
  end

  def notify_user_of_listing(listing)
    if @user_webhook_url
      send_webhook_notification(listing)
    else
      send_email_notification(listing)
    end
  end

  def send_webhook_notification(listing)
    uri = URI(@user_webhook_url)
    response = Net::HTTP.post_form(uri, 'url' => listing[:url])
    response.is_a?(Net::HTTPSuccess)
  end

  def send_email_notification(listing)
    Mailer.send_email(
      subject: 'New Apartment Listing Found!',
      body: "Found a new listing: #{listing[:url]}",
      to: 'user@example.com'
    )
  end
end

class Mailer
  def self.setup(options)
    Mail.defaults { delivery_method :smtp, options }
  end

  def self.send_email(subject:, body:, to:, from: 'noreply@nav.no')
    mail = Mail.new do
      from from
      to to
      subject subject
      body body
    end
    mail.deliver!
  rescue StandardError => e
    puts "Failed to send email: #{e.message}"
  end
end

if __FILE__ == $0
  api_key = ENV['API_KEY'] || raise('API key not set')
  hunter = ApartmentHunter.new(api_key)
  hunter.monitor_listings
end
