# frozen_string_literal: true

module Git
  module Pkgs
    module Models
      class DependencyChange < ActiveRecord::Base
        belongs_to :commit
        belongs_to :manifest

        validates :name, presence: true
        validates :change_type, presence: true, inclusion: { in: %w[added modified removed] }

        scope :added, -> { where(change_type: "added") }
        scope :modified, -> { where(change_type: "modified") }
        scope :removed, -> { where(change_type: "removed") }
        scope :for_package, ->(name) { where(name: name) }
        scope :for_platform, ->(platform) { where(ecosystem: platform) }

        def purl(with_version: true)
          version = with_version && manifest&.kind == "lockfile" ? requirement : nil
          PurlHelper.build_purl(ecosystem: ecosystem, name: name, version: version)
        end
      end
    end
  end
end
