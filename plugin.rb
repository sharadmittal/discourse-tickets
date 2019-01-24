# name: discourse-tickets
# about: Tickets system for Discourse
# version: 0.1
# authors:
# url: https://github.com/angusmcleod/discourse-tickets

register_asset 'stylesheets/tickets.scss'

load File.expand_path('../lib/tickets/validator.rb', __FILE__)

after_initialize do
  load File.expand_path('../lib/tickets/engine.rb', __FILE__)
  load File.expand_path("../lib/tickets/guardian.rb", __FILE__)
  load File.expand_path('../lib/tickets/routes.rb', __FILE__)
  load File.expand_path("../lib/tickets/topic.rb", __FILE__)
  load File.expand_path("../lib/tickets/ticket.rb", __FILE__)
  load File.expand_path("../lib/tickets/tag.rb", __FILE__)
  load File.expand_path("../controllers/tickets/tickets_controller.rb", __FILE__)
  load File.expand_path("../serializers/tickets/ticket_serializer.rb", __FILE__)

  register_seedfu_fixtures(Rails.root.join("plugins", "discourse-tickets", "db", "fixtures").to_s)

  add_class_method(:site, :ticket_tags) do
    Tag.joins('JOIN tag_group_memberships ON tags.id = tag_group_memberships.tag_id')
      .joins('JOIN tag_groups ON tag_group_memberships.tag_group_id = tag_groups.id')
      .where('tag_groups.name in (?)', Tickets::Tag::GROUPS)
      .group('tag_groups.name, tags.name', 'tag_group_memberships.created_at')
      .order('tag_group_memberships.created_at')
      .pluck('tag_groups.name, tags.name')
      .each_with_object({}) do |arr, result|
        type = arr[0].split("_").last
        result[type] = [] if result[type].blank?
        result[type].push(arr[1])
      end
  end

  module DiscourseTaggingExtension
    def filter_allowed_tags(query, guardian, opts = {})
      query = super(query, guardian, opts)

      if opts[:for_input]
        query = query.where('tags.id NOT IN (
          SELECT tag_id FROM tag_group_memberships
          WHERE tag_group_id IN (
            SELECT id FROM tag_groups
            WHERE name IN (?)
          )
        )', Tickets::Tag::GROUPS)
      end

      query
    end
  end

  require_dependency 'discourse_tagging'
  class << DiscourseTagging
    prepend DiscourseTaggingExtension
  end

  module ReceiverUserNameExtension
    def find_or_create_user(email, display_name, raise_on_failed_create: false)
      user = nil

      User.transaction do
        user = User.find_by_email(email)

        if user.nil? && SiteSetting.enable_staged_users
          raise EmailNotAllowed unless EmailValidator.allowed?(email)

          if (display_name)
            username = display_name[0] << rand(1000000).to_s
          else
            username = rand(1000000).to_s
          end
          Rails.logger.error ("Suggested username = #{username}")
          #username = UserNameSuggester.sanitize_username(display_name) if display_name.present?
          begin
            user = User.create!(
              email: email,
              username: UserNameSuggester.suggest(username.presence || email),
              name: display_name.presence || User.suggest_name(email),
              staged: true
            )
            @staged_users << user
          rescue PG::UniqueViolation, ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
            raise if raise_on_failed_create
            user = nil
          end
        end
      end

      user
    end
  end

  require_dependency 'email/receiver'
  class Email::Receiver
    prepend ReceiverUserNameExtension
  end

  require_dependency 'user_notifications'
  module UserNotificationsHelperExtension
    def show_username_on_post(post)
      return false
    end
  end

  class UserNotifications::UserNotificationRenderer
    prepend UserNotificationsHelperExtension

    #prepend_view_path File.expand_path("../custom_views", __FILE__)
    #def layout
    #  File.expand_path('../app/views/email/revisedpost.html.erb', __FILE__)
    #end
  end

  module ::UserNotificationsOverride
    def send_notification_email(opts)
        Rails.configuration.paths["app/views"].unshift(File.expand_path("../templates", __FILE__))
        super(opts)
    end
  end

  class ::UserNotifications
    prepend ::UserNotificationsOverride
  end

  DiscourseEvent.on(:post_created) do |post, opts, user|
    topic = Topic.find(post.topic_id)
    if post.is_first_post?
      #topic = Topic.find(post.topic_id)

      #guardian = Guardian.new(user)
      #guardian.ensure_can_create_ticket!(topic)

      topic.custom_fields['is_ticket'] = true
      # The new ticket will be marked open in below loop
      topic.save!
    end

    # Lets mark the ticket open
    unless !post.via_email
      # Remove the resolved tag
      topic_tags = topic.tags
      resolved_tag = topic_tags.find_by_name("resolved")
      if resolved_tag
        topic_tags.delete(resolved_tag)
        Rails.logger.error ("Deleting resolved tag")
      end
      open_tag = Tag.find_by_name("open")
      unless topic.tags.pluck(:id).include?(open_tag.id)
        topic.tags << open_tag
        Rails.logger.error ("Added open tag")
      end
      topic.save!
      post.publish_change_to_clients!(:revised, reload_topic: true)
    end
  end

  add_to_serializer(:site, :ticket_tags) { ::Site.ticket_tags }
  add_to_serializer(:site, :include_ticket_tags?) { SiteSetting.tickets_enabled }
end
