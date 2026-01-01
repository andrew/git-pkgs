# frozen_string_literal: true

module Git
  module Pkgs
    module Commands
      class Stats
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

          branch_name = @options[:branch] || repo.default_branch
          branch = Models::Branch.find_by(name: branch_name)

          data = collect_stats(branch, branch_name)

          if @options[:format] == "json"
            require "json"
            puts JSON.pretty_generate(data)
          else
            output_text(data)
          end
        end

        def collect_stats(branch, branch_name)
          data = {
            branch: branch_name,
            commits_analyzed: branch&.commits&.count || 0,
            commits_with_changes: branch&.commits&.where(has_dependency_changes: true)&.count || 0,
            current_dependencies: {},
            changes: {},
            most_changed: [],
            manifests: []
          }

          if branch&.last_analyzed_sha
            current_commit = Models::Commit.find_by(sha: branch.last_analyzed_sha)
            snapshots = current_commit&.dependency_snapshots || []

            data[:current_dependencies] = {
              total: snapshots.count,
              by_platform: snapshots.group(:ecosystem).count,
              by_type: snapshots.group(:dependency_type).count
            }
          end

          data[:changes] = {
            total: Models::DependencyChange.count,
            by_type: Models::DependencyChange.group(:change_type).count
          }

          most_changed = Models::DependencyChange
            .group(:name, :ecosystem)
            .order("count_all DESC")
            .limit(10)
            .count

          data[:most_changed] = most_changed.map do |(name, ecosystem), count|
            { name: name, ecosystem: ecosystem, changes: count }
          end

          data[:manifests] = Models::Manifest.all.map do |manifest|
            { path: manifest.path, ecosystem: manifest.ecosystem, changes: manifest.dependency_changes.count }
          end

          data
        end

        def output_text(data)
          puts "Dependency Statistics"
          puts "=" * 40
          puts

          puts "Branch: #{data[:branch]}"
          puts "Commits analyzed: #{data[:commits_analyzed]}"
          puts "Commits with changes: #{data[:commits_with_changes]}"
          puts

          if data[:current_dependencies][:total]
            puts "Current Dependencies"
            puts "-" * 20
            puts "Total: #{data[:current_dependencies][:total]}"

            data[:current_dependencies][:by_platform].sort_by { |_, c| -c }.each do |ecosystem, count|
              puts "  #{ecosystem}: #{count}"
            end

            by_type = data[:current_dependencies][:by_type]
            if by_type.keys.compact.any?
              puts
              puts "By type:"
              by_type.sort_by { |_, c| -c }.each do |type, count|
                puts "  #{type || 'unknown'}: #{count}"
              end
            end
          end

          puts
          puts "Dependency Changes"
          puts "-" * 20
          puts "Total changes: #{data[:changes][:total]}"
          data[:changes][:by_type].each do |type, count|
            puts "  #{type}: #{count}"
          end

          puts
          puts "Most Changed Dependencies"
          puts "-" * 25
          data[:most_changed].each do |dep|
            puts "  #{dep[:name]} (#{dep[:ecosystem]}): #{dep[:changes]} changes"
          end

          puts
          puts "Manifest Files"
          puts "-" * 14
          data[:manifests].each do |m|
            puts "  #{m[:path]} (#{m[:ecosystem]}): #{m[:changes]} changes"
          end
        end

        def parse_options
          options = {}

          parser = OptionParser.new do |opts|
            opts.banner = "Usage: git pkgs stats [options]"

            opts.on("-b", "--branch=NAME", "Branch to analyze") do |v|
              options[:branch] = v
            end

            opts.on("-f", "--format=FORMAT", "Output format (text, json)") do |v|
              options[:format] = v
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
