class IngestEvent < ApplicationRecord
  include IngestEventContext
  include IngestEventDetailing
  include IngestEventReporting

  belongs_to :project
  belongs_to :api_key
  belongs_to :error_group, optional: true
  has_one    :error_occurrence, dependent: :destroy

  before_validation :ensure_uuid

  enum :event_type, { error: 0, metric: 1, transaction: 2, log: 3, check_in: 4 }, validate: true, scopes: false

  validates :uuid, presence: true, uniqueness: true
  validates :message, presence: true
  validates :occurred_at, presence: true

  def to_param
    uuid
  end

  scope :db_queries, -> { where(event_type: :metric, message: "db.query") }
  scope :transactions, -> { where(event_type: :transaction) }
  scope :logs, -> { where(event_type: :log) }
  scope :check_ins, -> { where(event_type: :check_in) }
  scope :recent_db_queries, ->(since, limit = 300) {
    db_queries.where("occurred_at >= ?", since).order(occurred_at: :desc).limit(limit)
  }
  scope :recent_transactions, ->(since, limit = 300) {
    transactions.where("occurred_at >= ?", since).order(occurred_at: :desc).limit(limit)
  }
  scope :released, -> { where("COALESCE(context->>'release', '') <> ''") }

  private

  def ensure_uuid = self.uuid ||= SecureRandom.uuid
end
