# frozen_string_literal: true

class RenameVerifiedAppleSymbolArtifactStatus < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE apple_symbol_artifacts
      SET status = 'verified'
      WHERE status = 'ready'
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE apple_symbol_artifacts
      SET status = 'ready'
      WHERE status = 'verified'
    SQL
  end
end
