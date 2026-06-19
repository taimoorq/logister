class IngestEvent < ApplicationRecord
  PARTITION_REFERENCE_BATCH_SIZE = 200

  self.primary_key = :id

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

  def self.for_partition_references(records, id_key:, occurred_at_key:)
    partition_reference_relation(
      partition_references(records, id_key: id_key, occurred_at_key: occurred_at_key)
    )
  end

  def self.partition_reference_records(
    records,
    id_key:,
    occurred_at_key:,
    batch_size: PARTITION_REFERENCE_BATCH_SIZE,
    includes: nil
  )
    references = partition_references(records, id_key: id_key, occurred_at_key: occurred_at_key)
    return [] if references.empty?

    slice_size = [ batch_size.to_i, 1 ].max
    references.each_slice(slice_size).flat_map do |reference_batch|
      relation = partition_reference_relation(reference_batch)
      relation = relation.includes(*Array(includes)) if includes.present?
      relation.to_a
    end
  end

  def self.partition_reference_index(
    records,
    id_key:,
    occurred_at_key:,
    batch_size: PARTITION_REFERENCE_BATCH_SIZE,
    includes: nil
  )
    partition_reference_records(
      records,
      id_key: id_key,
      occurred_at_key: occurred_at_key,
      batch_size: batch_size,
      includes: includes
    ).index_by(&:id)
  end

  def self.for_partition_reference(id:, occurred_at:)
    for_partition_references(
      [ { id: id, occurred_at: occurred_at } ],
      id_key: :id,
      occurred_at_key: :occurred_at
    )
  end

  def self.partition_references(records, id_key:, occurred_at_key:)
    Array(records).filter_map do |record|
      id = partition_reference_value(record, id_key)
      next if id.blank?

      [ id, partition_reference_value(record, occurred_at_key) ]
    end.uniq
  end
  private_class_method :partition_references

  def self.partition_reference_relation(references)
    return none if references.empty?

    references_with_timestamps, references_without_timestamps = references.partition { |_id, occurred_at| occurred_at.present? }
    relation = none

    if references_with_timestamps.any?
      event_table = arel_table
      timestamp_conditions = references_with_timestamps.map do |id, occurred_at|
        event_table[:id].eq(id).and(event_table[:occurred_at].eq(occurred_at))
      end
      relation = relation.or(where(timestamp_conditions.reduce { |left, right| left.or(right) }))
    end

    if references_without_timestamps.any?
      relation = relation.or(where(id: references_without_timestamps.map(&:first)))
    end

    relation
  end
  private_class_method :partition_reference_relation

  def self.partition_reference_value(record, key)
    if record.respond_to?(key)
      record.public_send(key)
    elsif record.respond_to?(:[])
      record[key] || record[key.to_s]
    end
  end
  private_class_method :partition_reference_value

  private

  def ensure_uuid = self.uuid ||= SecureRandom.uuid
end
