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

  DiscourseEvent.on(:post_created) do |post, opts, user|
    topic = Topic.find(post.topic_id)
    if post.is_first_post?
      #topic = Topic.find(post.topic_id)

      #guardian = Guardian.new(user)
      #guardian.ensure_can_create_ticket!(topic)

      topic.custom_fields['is_ticket'] = true
      # The new ticket will be marked open in below unless loop
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
        # remove the resolved tag.
        # Todo : make sure no other tag types are possible for Status
      end
      topic.save!
      post.publish_change_to_clients!(:revised, reload_topic: true)
    end
  end

  add_to_serializer(:site, :ticket_tags) { ::Site.ticket_tags }
  add_to_serializer(:site, :include_ticket_tags?) { SiteSetting.tickets_enabled }
end
