# frozen_string_literal: true

class TelemetryDeliveryReplayJob < ApplicationJob
  queue_as :projector

  discard_on ActiveRecord::RecordNotFound

  def perform(delivery_id, replay_metadata = {})
    delivery = TelemetryDelivery.find(delivery_id)
    deliveries = if delivery.batch_key.present?
      TelemetryDelivery.where(batch_key: delivery.batch_key, status: :terminal_failed).order(:id)
    else
      TelemetryDelivery.where(id: delivery.id, status: :terminal_failed)
    end
    return if deliveries.empty?

    deliveries.each { |candidate| candidate.replay!(metadata: replay_metadata) }
    TelemetryProjectorJob.wake!
  end
end
