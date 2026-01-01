# frozen_string_literal: true

module Git
  module Pkgs
    module Commands
      class Diff
        def initialize(args)
          @args = args
          @options = parse_options
        end

        def run
          repo = Repository.new

          unless Database.exists?(repo.git_dir)
            $stderr.puts "Database not initialized. Run 'git pkgs init' first."
            exit 1
          end

          Database.connect(repo.git_dir)

          from_sha = @options[:from]
          to_sha = @options[:to] || repo.head_sha

          unless from_sha
            $stderr.puts "Usage: git pkgs diff --from=SHA [--to=SHA]"
            exit 1
          end

          from_commit = Models::Commit.find_by(sha: from_sha) ||
                        Models::Commit.where("sha LIKE ?", "#{from_sha}%").first
          to_commit = Models::Commit.find_by(sha: to_sha) ||
                      Models::Commit.where("sha LIKE ?", "#{to_sha}%").first

          unless from_commit
            $stderr.puts "Commit '#{from_sha}' not found in database"
            exit 1
          end

          unless to_commit
            $stderr.puts "Commit '#{to_sha}' not found in database"
            exit 1
          end

          # Get all changes between the two commits
          changes = Models::DependencyChange
            .includes(:commit, :manifest)
            .joins(:commit)
            .where("commits.committed_at > ? AND commits.committed_at <= ?",
                   from_commit.committed_at, to_commit.committed_at)
            .order("commits.committed_at ASC")

          if @options[:ecosystem]
            changes = changes.where(ecosystem: @options[:ecosystem])
          end

          if changes.empty?
            puts "No dependency changes between #{from_commit.short_sha} and #{to_commit.short_sha}"
            return
          end

          puts "Dependency changes from #{from_commit.short_sha} to #{to_commit.short_sha}:"
          puts

          added = changes.select { |c| c.change_type == "added" }
          modified = changes.select { |c| c.change_type == "modified" }
          removed = changes.select { |c| c.change_type == "removed" }

          if added.any?
            puts "Added:"
            added.group_by(&:name).each do |name, pkg_changes|
              latest = pkg_changes.last
              puts "  + #{name} #{latest.requirement} (#{latest.manifest.path})"
            end
            puts
          end

          if modified.any?
            puts "Modified:"
            modified.group_by(&:name).each do |name, pkg_changes|
              first = pkg_changes.first
              latest = pkg_changes.last
              puts "  ~ #{name} #{first.previous_requirement} -> #{latest.requirement}"
            end
            puts
          end

          if removed.any?
            puts "Removed:"
            removed.group_by(&:name).each do |name, pkg_changes|
              latest = pkg_changes.last
              puts "  - #{name} (was #{latest.requirement})"
            end
            puts
          end

          # Summary
          puts "Summary: +#{added.map(&:name).uniq.count} -#{removed.map(&:name).uniq.count} ~#{modified.map(&:name).uniq.count}"
        end

        def parse_options
          options = {}

          parser = OptionParser.new do |opts|
            opts.banner = "Usage: git pkgs diff --from=SHA [--to=SHA] [options]"

            opts.on("-f", "--from=SHA", "Start commit (required)") do |v|
              options[:from] = v
            end

            opts.on("-t", "--to=SHA", "End commit (default: HEAD)") do |v|
              options[:to] = v
            end

            opts.on("-e", "--ecosystem=NAME", "Filter by ecosystem") do |v|
              options[:ecosystem] = v
            end

            opts.on("-h", "--help", "Show this help") do
              puts opts
              exit
            end
          end

          parser.parse!(@args)
          options
        end
      end
    end
  end
end
