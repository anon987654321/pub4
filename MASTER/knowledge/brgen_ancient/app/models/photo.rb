# == Schema Information
#
# Table name: photos
#
#  id                                :integer          not null, primary key
#  post_id                           :integer
#  created_at                        :datetime
#  updated_at                        :datetime
#  attachment_file_name              :string
#  attachment_content_type           :string
#  attachment_file_size              :integer
#  attachment_updated_at             :datetime
#  processed_attachment_file_name    :string
#  processed_attachment_content_type :string
#  processed_attachment_file_size    :integer
#  processed_attachment_updated_at   :datetime
#  filter_data                       :text
#  attachment_animated               :boolean
#

class Photo < ActiveRecord::Base
  attr_accessor :applicable_styles

  belongs_to :post, class_name: "Forem::Post"

  # -------------------------------------------------

  has_attached_file :attachment,
    styles: lambda { |attachment|
      attachment.instance.setup_styles_in_background
    },

    # Make paths more sensible

    # Avoid `InfiniteInterpolationError`: http://goo.gl/enee1P

    path: ":rails_root/public/system/attachments/:id/:style/:filename",
    url: "/system/attachments/:id/:style/:filename"

  has_attached_file :processed_attachment,
    styles: {
      medium: "480x",
      thumbnail: "70x70#"
    },
    path: ":rails_root/public/system/processed_attachments/:id/:style/:filename",
    url: "/system/processed_attachments/:id/:style/:filename"

  # -------------------------------------------------

  before_post_process :setup_styles
  before_save :set_attachment_is_animated

  # -------------------------------------------------

  validates_attachment :attachment, presence: true, content_type: {
    content_type: ["image/jpg", "image/jpeg", "image/png", "image/gif", "video/mp4"],

    # TODO: I18n

    message: "Only images and videos are supported"
  }

  # -------------------------------------------------

  # Delayed Paperclip

  process_in_background :attachment

  # -------------------------------------------------

  def attachment_url(style = :medium)
    setup_styles
    style = video? ? :original : self.attachment_animated? ? "#{style.to_s}_animated".to_sym : style
    attachment.url(style)
  end

  def setup_styles
    @applicable_styles ||= (self.attachment_animated? ? video_styles : default_styles)
  end

  def setup_styles_in_background
    @applicable_styles ||= (self.attachment_animated? ? video_styles : default_styles)
  end

  def delete_old_gif
    File.unlink(self.attachment.path) if File.exist?(self.attachment.path)
  end

private
  def video_styles

    # Convert to MP4

    # http://goo.gl/EWK5bn

    {
      medium_animated: {
        format: "mp4",
        convert_options: {
          output: {

            # Use x264 for the H.264/MPEG-4 AVC format

            :"vcodec" => "libx264",

            # Y'UV420p pixel format for Firefox

            :"pix_fmt" => "yuv420p",

            # H.264 `baseline` profile for Android and iOS

            :"profile:v" => "baseline",

            # Slower encoding to improve quality

            :"preset" => "slower",

            # Lower the constant rate factor to improve quality

            :"crf" => 18,

            # Prevent height / width errors

            :"vf" => "scale='trunc(iw / 2) * 2 : trunc(ih / 2) * 2'"
          }
        },
        streaming: true,
        processors: [:transcoder, :qtfaststart]
      },
      thumbnail: {
        format: "jpg",
        time: 0.1,
        processors: [:transcoder]
      }
    }
  end

  def default_styles

    # Process as regular photos

    # paperclip-optimizer: Include `:thumbnail` to retain Paperclip's geometry functionality

    {
      medium: "480x",
      thumbnail: "70x70#",
      processors: [:thumbnail, :paperclip_optimizer]
    }
  end

  def animated_gif?
    return false if video?
    attachment_path = attachment.queued_for_write[:original] ? attachment.queued_for_write[:original].path : attachment.path
    # return false unless File.exist?(attachment.path)
    rmagick = Magick::ImageList.new(attachment_path)
    attachment.content_type =~ /gif/ && rmagick.scene > 0
  end

  def video?
    attachment.content_type =~ /video/
  end

  def set_attachment_is_animated
    self.attachment_animated = true if video? || animated_gif?
  end
end

