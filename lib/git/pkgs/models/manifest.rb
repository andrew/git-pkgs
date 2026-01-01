# frozen_string_literal: true

module Git
  module Pkgs
    module Models
      class Manifest < ActiveRecord::Base
        has_many :dependency_changes, dependent: :destroy
        has_many :dependency_snapshots, dependent: :destroy

        validates :path, presence: true

        def self.find_or_create(path:, ecosystem:, kind:)
          find_or_create_by(path: path) do |m|
            m.ecosystem = ecosystem
            m.kind = kind
          end
        end
      end
    end
  end
end
