# frozen_string_literal: true

module ProjectAccess
  extend ActiveSupport::Concern

  def owned_by?(viewer)
    viewer.present? && user_id == viewer.id
  end

  def managed_by?(viewer)
    return false unless viewer

    owned_by?(viewer) || project_memberships.admin.exists?(user_id: viewer.id)
  end

  def notification_recipients
    User.where(id: assignable_user_ids).distinct
  end

  def assignable_users
    User.where(id: assignable_user_ids).order(:email)
  end

  def assignable_user?(user)
    user.present? && assignable_user_ids.include?(user.id)
  end

  def assignable_user_ids
    @assignable_user_ids ||= [ user_id, *project_memberships.pluck(:user_id) ].uniq
  end
end
