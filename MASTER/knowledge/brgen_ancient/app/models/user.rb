# == Schema Information
#
# Table name: users
#
#  id                     :integer          not null, primary key
#  created_at             :datetime
#  updated_at             :datetime
#  email                  :string           default(""), not null
#  encrypted_password     :string           default(""), not null
#  reset_password_token   :string
#  reset_password_sent_at :datetime
#  remember_created_at    :datetime
#  sign_in_count          :integer          default("0")
#  current_sign_in_at     :datetime
#  last_sign_in_at        :datetime
#  current_sign_in_ip     :string
#  last_sign_in_ip        :string
#  forem_admin            :boolean          default("false")
#  forem_state            :string           default("pending_review")
#  forem_auto_subscribe   :boolean          default("false")
#  name                   :string
#  country                :string
#  gender                 :string
#  username               :string
#  persistence_token      :string
#  avatar_file_name       :string
#  avatar_content_type    :string
#  avatar_file_size       :integer
#  avatar_updated_at      :datetime
#

class User < ActiveRecord::Base
  has_many :posts, :class_name => "Forem::Post", :dependent => :destroy
  has_many :topics, :class_name => "Forem::Topic", :dependent => :destroy
  has_many :likes
  has_many :authentications

  devise :database_authenticatable, :registerable, :recoverable, :rememberable, :trackable, :validatable, :omniauthable, :omniauth_providers => [:facebook, :google_oauth2]

  has_attached_file :avatar, default_url: "/images/:style/missing.png"

  validates_attachment_content_type :avatar, content_type: /\Aimage\/.*\Z/

  validates :name, :presence => { :message => I18n.t(:cant_be_blank) }
  validates :gender, :presence => { :message => I18n.t(:cant_be_blank) }
  validates :username, :presence => { :message => I18n.t(:cant_be_blank) }, :uniqueness => true

  # -------------------------------------------------

  def to_s
    anonymous? ? I18n.t(:anonymous) : name
  end

  # -------------------------------------------------

  def build_or_update_authentication(auth_hash)
    auth = authentications.where(provider: auth_hash.provider, uid: auth_hash.uid).first || authentications.build
    auth.provider = auth_hash.provider
    auth.uid = auth_hash.uid
    auth.name = auth_hash.info.name
    auth.oauth_token = auth_hash.credentials.token
    auth.oauth_expires_at = Time.at(auth_hash.credentials.expires_at)

    if !self.try(:new_record?)
      auth.save!
    end
  end

  # -------------------------------------------------

  def facebook_user?
    @facebook_auth ||= authentications.find_by_provider("facebook")
  end

  def facebook
    @facebook ||= Koala::Facebook::API.new(facebook_oauth_token)
  end

  def facebook_oauth_token
    @facebook_auth.oauth_token if facebook_user?
  end

  def facebook_picture(options)
    type = options.delete(:size) || "square"
    picture = facebook.get_object("me/picture?redirect=false?type=#{ type }")

    if picture["data"]["url"]
      picture["data"]["url"]
    else
      avatar.url(:thumb)
    end
  end

  # -------------------------------------------------

  # Create anonymous user

  def self.anonymous!
    token = User.generate_token(:persistence_token)
    User.create(:email => "#{ token }@example.com", :password => token, :password_confirmation => token, :persistence_token => token, :username => token, :gender => "male", :name => token)
  end

  def anonymous?
    email =~ /@example.com$/
  end

  def generate_anon_id
    self.anon_id = SecureRandom.hex
  end

  # -------------------------------------------------

  def has_like?(post)
    likes.find_by_post_id(post.id)
  end

private

  # Generate a friendly random string to be used as a token

  def self.friendly_token
    SecureRandom.base64(15).tr('+/=', '-_ ').strip.delete("\n")
  end

  # Generate a token by looping and ensuring it doesn't already exist

  def self.generate_token(column)
    loop do
      token = friendly_token
      break token unless where(column => token).first
    end
  end
end

