# frozen_string_literal: true

module Git
  module Pkgs
    module Models
      class Commit < ActiveRecord::Base
        has_many :branch_commits, dependent: :destroy
        has_many :branches, through: :branch_commits
        has_many :dependency_changes, dependent: :destroy
        has_many :dependency_snapshots, dependent: :destroy

        validates :sha, presence: true, uniqueness: true

        def self.find_or_create_from_rugged(rugged_commit)
          find_or_create_by(sha: rugged_commit.oid) do |commit|
            commit.message = rugged_commit.message&.strip
            commit.author_name = rugged_commit.author[:name]
            commit.author_email = rugged_commit.author[:email]
            commit.committed_at = rugged_commit.time
          end
        end

        def self.find_or_create_from_repo(repo, sha)
          commit = find_by(sha: sha) || where("sha LIKE ?", "#{sha}%").first
          return commit if commit

          rugged_commit = repo.lookup(sha)
          return nil unless rugged_commit

          create!(
            sha: rugged_commit.oid,
            message: rugged_commit.message,
            author_name: rugged_commit.author[:name],
            author_email: rugged_commit.author[:email],
            committed_at: rugged_commit.time,
            has_dependency_changes: false
          )
        rescue Rugged::OdbError
          nil
        end

        def short_sha
          sha[0, 7]
        end
      end
    end
  end
end
