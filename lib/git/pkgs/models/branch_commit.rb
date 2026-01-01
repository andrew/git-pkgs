# frozen_string_literal: true

module Git
  module Pkgs
    module Models
      class BranchCommit < ActiveRecord::Base
        belongs_to :branch
        belongs_to :commit

        validates :branch_id, uniqueness: { scope: :commit_id }
      end
    end
  end
end
