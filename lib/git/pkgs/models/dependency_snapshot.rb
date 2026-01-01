# frozen_string_literal: true

module Git
  module Pkgs
    module Models
      class DependencySnapshot < ActiveRecord::Base
        belongs_to :commit
        belongs_to :manifest

        validates :name, presence: true

        scope :for_package, ->(name) { where(name: name) }
        scope :for_platform, ->(platform) { where(ecosystem: platform) }
        scope :at_commit, ->(commit) { where(commit: commit) }

        def self.current_for_branch(branch)
          return none unless branch.last_analyzed_sha

          commit = Commit.find_by(sha: branch.last_analyzed_sha)
          return none unless commit

          where(commit: commit)
        end
      end
    end
  end
end
