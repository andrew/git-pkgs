# frozen_string_literal: true

module Git
  module Pkgs
    module Commands
      class History
        def initialize(args)
          @args = args
          @options = parse_options
        end

        def run
          package_name = @args.shift

          unless package_name
            $stderr.puts "Usage: git pkgs history <package>"
            exit 1
          end

          repo = Repository.new

          unless Database.exists?(repo.git_dir)
            $stderr.puts "Database not initialized. Run 'git pkgs init' first."
            exit 1
          end

          Database.connect(repo.git_dir)

          changes = Models::DependencyChange
            .includes(:commit, :manifest)
            .for_package(package_name)
            .order("commits.committed_at ASC")

          if @options[:ecosystem]
            changes = changes.for_platform(@options[:ecosystem])
          end

          if changes.empty?
            puts "No history found for '#{package_name}'"
            return
          end

          if @options[:format] == "json"
            output_json(changes)
          else
            output_text(changes, package_name)
          end
        end

        def output_text(changes, package_name)
          puts "History for #{package_name}:"
          puts

          changes.each do |change|
            commit = change.commit
            date = commit.committed_at.strftime("%Y-%m-%d")

            case change.change_type
            when "added"
              action = "Added"
              version_info = change.requirement
            when "modified"
              action = "Updated"
              version_info = "#{change.previous_requirement} -> #{change.requirement}"
            when "removed"
              action = "Removed"
              version_info = change.requirement
            end

            puts "#{date} #{action} #{version_info}"
            puts "  Commit: #{commit.short_sha} #{commit.message&.lines&.first&.strip}"
            puts "  Author: #{commit.author_name} <#{commit.author_email}>"
            puts "  Manifest: #{change.manifest.path}"
            puts
          end
        end

        def output_json(changes)
          require "json"

          data = changes.map do |change|
            {
              date: change.commit.committed_at.iso8601,
              change_type: change.change_type,
              requirement: change.requirement,
              previous_requirement: change.previous_requirement,
              manifest: change.manifest.path,
              ecosystem: change.ecosystem,
              commit: {
                sha: change.commit.sha,
                message: change.commit.message&.lines&.first&.strip,
                author_name: change.commit.author_name,
                author_email: change.commit.author_email
              }
            }
          end

          puts JSON.pretty_generate(data)
        end

        def parse_options
          options = {}

          parser = OptionParser.new do |opts|
            opts.banner = "Usage: git pkgs history <package> [options]"

            opts.on("-e", "--ecosystem=NAME", "Filter by ecosystem") do |v|
              options[:ecosystem] = v
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
