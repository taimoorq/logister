class IngestEvent < ApplicationRecord
  belongs_to :project
  belongs_to :api_key

  enum :event_type, { error: 0, metric: 1 }, validate: true

  validates :message, presence: true
  validates :occurred_at, presence: true
end
