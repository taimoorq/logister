# frozen_string_literal: true

# Records the source IP that started a CLI device login so the browser approval
# page can show it next to the request time.
class AddRequestedIpToCliDeviceAuthorizations < ActiveRecord::Migration[8.1]
  def change
    add_column :cli_device_authorizations, :requested_ip, :string
  end
end
