# frozen_string_literal: true

class ReleaseDownload < ApplicationRecord
  belongs_to :release
  belongs_to :user, optional: true

  delegate :app, :channel, to: :release
end
