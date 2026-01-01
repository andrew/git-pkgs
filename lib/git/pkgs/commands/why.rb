# frozen_string_literal: true

module Git
  module Pkgs
    module Commands
      class Why
        def initialize(args)
          @args = args
          @options = parse_options
        end

        def run
          package_name = @args.shift

          unless package_name
            $stderr.puts "Usage: git pkgs why <package>"
            exit 1
          end

          repo = Repository.new

          unless Database.exists?(repo.git_dir)
            $stderr.puts "Database not initialized. Run 'git pkgs init' first."
            exit 1
          end

          Database.connect(repo.git_dir)

          # Find the first time this package was added
          added_change = Models::DependencyChange
            .includes(:commit, :manifest)
            .for_package(package_name)
            .added
            .order("commits.committed_at ASC")

          if @options[:ecosystem]
            added_change = added_change.for_platform(@options[:ecosystem])
          end

          added_change = added_change.first

          unless added_change
            puts "Package '#{package_name}' not found in dependency history"
            return
          end

          commit = added_change.commit

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

        def parse_options
          options = {}

          parser = OptionParser.new do |opts|
            opts.banner = "Usage: git pkgs why <package> [options]"

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
