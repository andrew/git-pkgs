# frozen_string_literal: true

module Git
  module Pkgs
    module Commands
      class Why
        include Output

        def initialize(args)
          @args = args
          @options = parse_options
        end

        def run
          package_name = @args.shift

          error "Usage: git pkgs why <package>" unless package_name

          repo = Repository.new
          require_database(repo)

          Database.connect(repo.git_dir)

          # Find the first time this package was added
          added_change = Models::DependencyChange
            .eager(:commit, :manifest)
            .for_package(package_name)
            .added
            .order("commits.committed_at ASC")

          if @options[:ecosystem]
            added_change = added_change.for_platform(@options[:ecosystem])
          end

          added_change = added_change.first

          unless added_change
            if @options[:format] == "json"
              require "json"
              puts JSON.pretty_generate({ found: false, package: package_name })
            else
              empty_result "Package '#{package_name}' not found in dependency history"
            end
            return
          end

          commit = added_change.commit

          if @options[:format] == "json"
            output_json(package_name, added_change, commit)
          else
            output_text(package_name, added_change, commit)
          end
        end

        def output_text(package_name, added_change, commit)
          puts "#{package_name} was added in commit #{commit.short_sha}"
          puts
          puts "Date:    #{commit.committed_at.strftime("%Y-%m-%d %H:%M")}"
          puts "Author:  #{commit.author_name} <#{commit.author_email}>"
          puts "Manifest: #{added_change.manifest.path}"
          puts "Version: #{added_change.requirement}"
          puts
          puts "Commit message:"
          puts commit.message.to_s.lines.map { |l| "  #{l}" }.join
        end

        def output_json(package_name, added_change, commit)
          require "json"

          data = {
            found: true,
            package: package_name,
            ecosystem: added_change.ecosystem,
            requirement: added_change.requirement,
            manifest: added_change.manifest.path,
            commit: {
              sha: commit.sha,
              short_sha: commit.short_sha,
              message: commit.message,
              author_name: commit.author_name,
              author_email: commit.author_email,
              date: commit.committed_at.iso8601
            }
          }

          puts JSON.pretty_generate(data)
        end

        def parse_options
          options = {}

          parser = OptionParser.new do |opts|
            opts.banner = "Usage: git pkgs why <package> [options]"

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
