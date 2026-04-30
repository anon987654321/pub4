class AdMailer < ActionMailer::Base
  default from: "brgen.no <#{ I18n.t(:noreply) }@brgen.no>"

  def ad_confirm(topic)
    @topic = topic

    mail(to: topic.posts.first.email, subject: "brgen.no - #{ t :confirm_your_ad }: #{ topic.subject }")
  end

  def ad_forward(topic, post)
    @topic = topic
    @post = post

    mail(to: topic.posts.first.email, subject: "brgen.no - #{ t :you_have_a_reply }: #{ topic.subject }", reply_to: post.email)
  end
end

