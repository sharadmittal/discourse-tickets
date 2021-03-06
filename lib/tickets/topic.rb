Topic.register_custom_field_type('is_ticket', :boolean)
TopicList.preloaded_custom_fields << 'is_ticket' if TopicList.respond_to? :preloaded_custom_fields

Topic.register_custom_field_type('order_id', :string)
TopicList.preloaded_custom_fields << 'order_id' if TopicList.respond_to? :preloaded_custom_fields

Topic.register_custom_field_type('locked_at', :integer)
TopicList.preloaded_custom_fields << 'locked_at' if TopicList.respond_to? :preloaded_custom_fields

Topic.register_custom_field_type('locked_by', :string)
TopicList.preloaded_custom_fields << 'locked_by' if TopicList.respond_to? :preloaded_custom_fields

require_dependency 'topic'
class Topic
  def is_ticket
    if custom_fields['is_ticket']
      ActiveModel::Type::Boolean.new.cast(custom_fields['is_ticket'])
    else
      false
    end
  end

  def order_id
    if custom_fields['order_id']
      custom_fields['order_id']
    else
      ""
    end
  end

  def locked_at
    if custom_fields['locked_at']
      ActiveModel::Type::Integer.new.cast(custom_fields['locked_at'])
    else
      0
    end
  end

  def locked_by
    if custom_fields['locked_by']
      ActiveModel::Type::String.new.cast(custom_fields['locked_by'])
    else
      ""
    end
  end
end

require_dependency 'topic_view_serializer'
class TopicViewSerializer
  attributes :is_ticket, :order_id

  def is_ticket
    object.topic.is_ticket
  end

  def order_id
    object.topic.order_id
  end
end

require_dependency 'topic_list_item_serializer'
class TopicListItemSerializer
  attributes :is_ticket, :order_id, :locked_at, :locked_by

  def is_ticket
    object.is_ticket
  end

  def order_id
    object.order_id
  end

  def locked_at
    object.locked_at
  end

  def locked_by
    object.locked_by
  end
end

PostRevisor.track_topic_field(:is_ticket) do |tc, is_ticket|
  if tc.guardian.can_create_ticket?(tc.topic)
    tc.record_change('is_ticket', tc.topic.is_ticket, is_ticket)
    tc.topic.custom_fields['is_ticket'] = ActiveModel::Type::Boolean.new.cast(is_ticket)
  end
end

PostRevisor.track_topic_field(:allowed_groups) do |tc, allowed_groups|
  tc.record_change('allowed_groups', tc.topic.allowed_groups, allowed_groups)

  names = allowed_groups.split(',').flatten
  Group.where(name: names).each do |group|
    tc.topic.topic_allowed_groups.build(group_id: group.id)
    group.update_columns(has_messages: true) unless group.has_messages
  end
end

PostRevisor.track_topic_field(:allowed_users) do |tc, allowed_users|
  tc.record_change('allowed_users', tc.topic.allowed_users, allowed_users)

  names = allowed_users.split(',').flatten

  User.includes(:user_option).where(username: names).find_each do |user|
    tc.topic.topic_allowed_users.build(user_id: user.id)
  end
end
