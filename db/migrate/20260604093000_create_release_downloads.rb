# frozen_string_literal: true

class CreateReleaseDownloads < ActiveRecord::Migration[8.1]
  def change
    create_table :release_downloads do |t|
      t.references :release, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.string :ip
      t.string :user_agent

      t.timestamps
    end

    add_index :release_downloads, :created_at
  end
end
