require Rails.root.join("lib/sendgrid_delivery_method")

ActionMailer::Base.add_delivery_method(
  :sendgrid_api,
  SendgridDeliveryMethod,
  api_key: ENV["SENDGRID_API_KEY"]
)
