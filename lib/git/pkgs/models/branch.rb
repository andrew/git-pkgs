# frozen_string_literal: true

module Git
  module Pkgs
    module Models
      class Branch < ActiveRecord::Base
        has_many :branch_commits, dependent: :destroy
        has_many :commits, through: :branch_commits

        validates :name, presence: true, uniqueness: true

        def self.find_or_create(name)
          find_or_create_by(name: name)
        end
      end
    end
  end
end
