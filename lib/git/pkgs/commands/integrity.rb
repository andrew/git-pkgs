# frozen_string_literal: true

module Git
  module Pkgs
    module Commands
      class Integrity
        include Output

        def self.description
          "Show and verify lockfile integrity hashes"
        end

        def initialize(args)
          @args = args
          @options = parse_options
        end

        def run
          repo = Repository.new
          use_stateless = @options[:stateless] || !Database.exists?(repo.git_dir)

          if @options[:drift]
            error "--drift requires database (run 'git pkgs init' first)" if use_stateless
            run_drift_detection(repo)
          else
            run_show(repo, use_stateless)
          end
        end

        def run_show(repo, use_stateless)
          if use_stateless
            deps = run_stateless(repo)
          else
            deps = run_with_database(repo)
          end

          # Filter to only lockfile deps with integrity
          deps = Analyzer.lockfile_dependencies(deps)
          deps = deps.select { |d| d[:integrity] }

          if @options[:ecosystem]
            deps = deps.select { |d| d[:ecosystem] == @options[:ecosystem] }
          end

          if deps.empty?
            empty_result "No dependencies with integrity hashes found"
            return
          end

          if @options[:format] == "json"
            require "json"
            puts JSON.pretty_generate(deps.map { |d| format_dep_json(d) })
          else
            paginate { output_text(deps) }
          end
        end

        def run_stateless(repo)
          commit_sha = @options[:ref] || repo.head_sha
          rugged_commit = repo.lookup(repo.rev_parse(commit_sha))
          error "Could not resolve '#{commit_sha}'" unless rugged_commit

          analyzer = Analyzer.new(repo)
          analyzer.dependencies_at_commit(rugged_commit)
        end

        def run_with_database(repo)
          Database.connect(repo.git_dir)

          commit_sha = @options[:ref] || repo.head_sha
          target_commit = Models::Commit.first(sha: commit_sha)
          error "Commit not in database. Run 'git pkgs update' first." unless target_commit

          compute_dependencies_at_commit(target_commit, repo)
        end

        def run_drift_detection(repo)
          Database.connect(repo.git_dir)

          # Get unique (purl, requirement, integrity) from snapshots
          results = Database.db[:dependency_snapshots]
            .exclude(integrity: nil)
            .select(:purl, :requirement, :integrity)
            .distinct
            .all

          # Build versioned purls and group
          by_versioned_purl = {}
          results.each do |r|
            versioned_purl = "#{r[:purl]}@#{r[:requirement]}"
            by_versioned_purl[versioned_purl] ||= { purl: r[:purl], version: r[:requirement], lockfile_integrities: [] }
            by_versioned_purl[versioned_purl][:lockfile_integrities] << r[:integrity]
          end

          # Dedupe lockfile integrities
          by_versioned_purl.each { |_, v| v[:lockfile_integrities].uniq! }

          # Find internal drift (same version with different lockfile hashes)
          internal_drifts = by_versioned_purl.select { |_, v| v[:lockfile_integrities].size > 1 }

          # Fetch registry integrity for comparison
          registry_mismatches = []
          purls_to_check = by_versioned_purl.keys

          if purls_to_check.any?
            Spinner.with_spinner("Fetching registry integrity...") do
              client = EcosystemsClient.new
              purls_to_check.each do |versioned_purl|
                data = by_versioned_purl[versioned_purl]
                version_info = client.lookup_version(versioned_purl)
                next unless version_info && version_info["integrity"]

                registry_integrity = version_info["integrity"]
                lockfile_integrity = data[:lockfile_integrities].first

                unless integrity_match?(lockfile_integrity, registry_integrity)
                  registry_mismatches << {
                    purl: versioned_purl,
                    lockfile: lockfile_integrity,
                    registry: registry_integrity
                  }
                end
              end
            end
          end

          if internal_drifts.empty? && registry_mismatches.empty?
            info "No integrity drift detected"
            return
          end

          if @options[:format] == "json"
            require "json"
            output = {
              internal_drift: internal_drifts.map { |purl, v| { purl: purl, integrity_values: v[:lockfile_integrities] } },
              registry_mismatch: registry_mismatches
            }
            puts JSON.pretty_generate(output)
          else
            paginate { output_drift_text(internal_drifts, registry_mismatches) }
          end
        end

        def integrity_match?(lockfile, registry)
          normalize_integrity(lockfile) == normalize_integrity(registry)
        end

        def normalize_integrity(integrity)
          return nil unless integrity
          # Normalize sha256= vs sha256- format
          integrity.gsub(/^sha256[-=]/, "sha256:")
        end

        def output_text(deps)
          grouped = deps.group_by { |d| d[:ecosystem] }

          grouped.each do |ecosystem, ecosystem_deps|
            puts "#{ecosystem}:"
            ecosystem_deps.sort_by { |d| d[:name] }.each do |dep|
              puts "  #{dep[:name]} #{dep[:requirement]}"
              puts "    #{dep[:integrity]}"
            end
            puts
          end
        end

        def output_drift_text(internal_drifts, registry_mismatches)
          if internal_drifts.any?
            puts Color.red("Internal drift (same version, different lockfile hashes):")
            puts
            internal_drifts.each do |purl, data|
              puts "  #{purl}"
              data[:lockfile_integrities].each do |integrity|
                puts "    #{integrity}"
              end
              puts
            end
          end

          if registry_mismatches.any?
            puts Color.red("Registry mismatch (lockfile differs from registry):")
            puts
            registry_mismatches.each do |mismatch|
              puts "  #{mismatch[:purl]}"
              puts "    lockfile: #{mismatch[:lockfile]}"
              puts "    registry: #{mismatch[:registry]}"
              puts
            end
          end

          total = internal_drifts.size + registry_mismatches.size
          puts "#{total} integrity issue(s) found"
        end

        def format_dep_json(dep)
          {
            name: dep[:name],
            version: dep[:requirement],
            ecosystem: dep[:ecosystem],
            purl: dep[:purl],
            integrity: dep[:integrity],
            manifest: dep[:manifest_path]
          }
        end

        def compute_dependencies_at_commit(target_commit, repo)
          branch_name = @options[:branch] || repo.default_branch
          branch = Models::Branch.first(name: branch_name)
          return [] unless branch

          snapshot_commit = branch.commits_dataset
            .join(:dependency_snapshots, commit_id: :id)
            .where { Sequel[:commits][:committed_at] <= target_commit.committed_at }
            .order(Sequel.desc(Sequel[:commits][:committed_at]))
            .distinct
            .first

          deps = {}
          if snapshot_commit
            snapshot_commit.dependency_snapshots.each do |s|
              key = [s.manifest.path, s.name]
              deps[key] = {
                manifest_path: s.manifest.path,
                name: s.name,
                ecosystem: s.ecosystem,
                kind: s.manifest.kind,
                manifest_kind: s.manifest.kind,
                purl: s.purl,
                requirement: s.requirement,
                dependency_type: s.dependency_type,
                integrity: s.integrity
              }
            end
          end

          deps.values
        end

        def parse_options
          options = {}

          parser = OptionParser.new do |opts|
            opts.banner = "Usage: git pkgs integrity [options]"
            opts.separator ""
            opts.separator "Show integrity hashes from lockfiles. Hashes come from lockfile checksums"
            opts.separator "(Gemfile.lock CHECKSUMS, package-lock.json integrity fields, etc.)"

            opts.on("-r", "--ref=REF", "Git ref to check (default: HEAD)") do |v|
              options[:ref] = v
            end

            opts.on("-e", "--ecosystem=NAME", "Filter by ecosystem") do |v|
              options[:ecosystem] = v
            end

            opts.on("-b", "--branch=NAME", "Branch context for database queries") do |v|
              options[:branch] = v
            end

            opts.on("-f", "--format=FORMAT", "Output format (text, json)") do |v|
              options[:format] = v
            end

            opts.on("--drift", "Detect packages with different hashes for same version") do
              options[:drift] = true
            end

            opts.on("--stateless", "Parse manifests directly without database") do
              options[:stateless] = true
            end

            opts.on("--no-pager", "Do not pipe output into a pager") do
              options[:no_pager] = true
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
