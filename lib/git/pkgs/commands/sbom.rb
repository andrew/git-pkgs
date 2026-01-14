# frozen_string_literal: true

require "optparse"
require "sbom"

module Git
  module Pkgs
    module Commands
      class Sbom
        include Output

        def self.description
          "Export dependencies as SBOM (SPDX or CycloneDX)"
        end

        def initialize(args)
          @args = args.dup
          @options = parse_options
        end

        def run
          repo = Repository.new
          use_stateless = @options[:stateless] || !Database.exists?(repo.git_dir)

          if use_stateless
            Database.connect_memory
            deps = get_dependencies_stateless(repo)
          else
            Database.connect(repo.git_dir)
            deps = get_dependencies_with_database(repo)
          end

          if deps.empty?
            empty_result "No dependencies found"
            return
          end

          if @options[:ecosystem]
            deps = deps.select { |d| d[:ecosystem].downcase == @options[:ecosystem].downcase }
          end

          deps = Analyzer.pair_manifests_with_lockfiles(deps)

          if deps.empty?
            empty_result "No dependencies found"
            return
          end

          packages = build_packages(deps)
          enrich_packages(packages) unless @options[:skip_enrichment]

          output_sbom(repo, packages)
        end

        def build_packages(deps)
          deps.map do |dep|
            purl = PurlHelper.build_purl(ecosystem: dep[:ecosystem], name: dep[:name], version: dep[:requirement])
            {
              purl: purl.to_s,
              name: dep[:name],
              ecosystem: dep[:ecosystem],
              version: dep[:requirement],
              integrity: dep[:integrity]
            }
          end.uniq { |p| p[:purl] }
        end

        def enrich_packages(packages)
          client = EcosystemsClient.new

          # Enrich package-level data (license, latest version)
          base_purls = packages.map { |p| PurlHelper.build_purl(ecosystem: p[:ecosystem], name: p[:name]).to_s }

          packages_by_purl = {}
          base_purls.each do |purl|
            parsed = Purl::PackageURL.parse(purl)
            ecosystem = PurlHelper::ECOSYSTEM_TO_PURL_TYPE.invert[parsed.type] || parsed.type
            pkg = Models::Package.find_or_create_by_purl(
              purl: purl,
              ecosystem: ecosystem,
              name: parsed.name
            )
            packages_by_purl[purl] = pkg
          end

          stale_pkg_purls = packages_by_purl.select { |_, pkg| pkg.needs_enrichment? }.keys

          if stale_pkg_purls.any?
            begin
              results = Spinner.with_spinner("Fetching package metadata...") do
                client.bulk_lookup(stale_pkg_purls)
              end
              results.each do |purl, data|
                packages_by_purl[purl]&.enrich_from_api(data)
              end
            rescue EcosystemsClient::ApiError => e
              $stderr.puts "Warning: Could not fetch package data: #{e.message}" unless Git::Pkgs.quiet
            end
          end

          # Enrich version-level data (integrity, published_at)
          versions_by_purl = {}
          packages.each do |pkg|
            base_purl = PurlHelper.build_purl(ecosystem: pkg[:ecosystem], name: pkg[:name]).to_s
            version = Models::Version.find_or_create_by_purl(
              purl: pkg[:purl],
              package_purl: base_purl
            )
            versions_by_purl[pkg[:purl]] = version
          end

          stale_version_purls = versions_by_purl.select { |_, v| v.needs_enrichment? }.keys

          if stale_version_purls.any?
            begin
              Spinner.with_spinner("Fetching version metadata...") do
                stale_version_purls.each do |purl|
                  data = client.lookup_version(purl)
                  versions_by_purl[purl]&.enrich_from_api(data) if data
                end
              end
            rescue EcosystemsClient::ApiError => e
              $stderr.puts "Warning: Could not fetch version data: #{e.message}" unless Git::Pkgs.quiet
            end
          end

          # Apply enriched data to packages
          packages.each do |pkg|
            base_purl = PurlHelper.build_purl(ecosystem: pkg[:ecosystem], name: pkg[:name]).to_s
            db_pkg = packages_by_purl[base_purl]
            db_version = versions_by_purl[pkg[:purl]]

            pkg[:license] ||= db_version&.license || db_pkg&.license
            pkg[:integrity] ||= db_version&.integrity
            pkg[:supplier_name] ||= db_pkg&.supplier_name
            pkg[:supplier_type] ||= db_pkg&.supplier_type
          end
        end

        def output_sbom(repo, packages)
          sbom_type = @options[:type]&.to_sym || :cyclonedx
          format = @options[:format]&.to_sym || :json

          generator = ::Sbom::Generator.new(sbom_type: sbom_type, format: format)

          sbom_packages = packages.map do |pkg|
            sbom_pkg = ::Sbom::Data::Package.new
            sbom_pkg.name = pkg[:name]
            sbom_pkg.version = pkg[:version]
            sbom_pkg.purl = pkg[:purl]
            sbom_pkg.license_concluded = pkg[:license] if pkg[:license]

            if pkg[:supplier_name]
              sbom_pkg.set_supplier(pkg[:supplier_type] || "organization", pkg[:supplier_name])
            end

            if pkg[:integrity]
              algorithm, hash = parse_integrity(pkg[:integrity])
              sbom_pkg.add_checksum(algorithm, hash) if algorithm && hash
            end

            sbom_pkg
          end

          project_name = @options[:name] || File.basename(repo.path)
          generator.generate(project_name, { packages: sbom_packages })
          puts generator.output
        end

        def parse_integrity(integrity)
          return nil unless integrity

          case integrity
          when /^sha256[-:=](.+)$/i
            ["SHA256", $1]
          when /^sha512[-:=](.+)$/i
            ["SHA512", $1]
          when /^sha1[-:=](.+)$/i
            ["SHA1", $1]
          when /^md5[-:=](.+)$/i
            ["MD5", $1]
          when /^h1:(.+)$/
            # Go modules use base64-encoded SHA256 in go.sum
            # SPDX/CycloneDX require hex, so convert
            require "base64"
            hex = Base64.decode64($1).unpack1("H*")
            ["SHA256", hex]
          else
            nil
          end
        end

        def parse_options
          options = {}

          parser = OptionParser.new do |opts|
            opts.banner = "Usage: git pkgs sbom [options]"
            opts.separator ""
            opts.separator "Export dependencies as SBOM (Software Bill of Materials)."
            opts.separator ""
            opts.separator "Options:"

            opts.on("-t", "--type=TYPE", "SBOM type: cyclonedx (default) or spdx") do |v|
              options[:type] = v.downcase
            end

            opts.on("-f", "--format=FORMAT", "Output format: json (default) or xml") do |v|
              options[:format] = v.downcase
            end

            opts.on("-n", "--name=NAME", "Project name (default: repository directory name)") do |v|
              options[:name] = v
            end

            opts.on("-e", "--ecosystem=NAME", "Filter by ecosystem") do |v|
              options[:ecosystem] = v
            end

            opts.on("-r", "--ref=REF", "Git ref to export (default: HEAD)") do |v|
              options[:ref] = v
            end

            opts.on("--skip-enrichment", "Skip fetching license data from registries") do
              options[:skip_enrichment] = true
            end

            opts.on("--stateless", "Parse manifests directly without database") do
              options[:stateless] = true
            end

            opts.on("-h", "--help", "Show this help") do
              puts opts
              exit
            end
          end

          parser.parse!(@args)
          options
        end

        def get_dependencies_stateless(repo)
          ref = @options[:ref] || "HEAD"
          commit_sha = repo.rev_parse(ref)
          rugged_commit = repo.lookup(commit_sha)

          error "Could not resolve '#{ref}'" unless rugged_commit

          analyzer = Analyzer.new(repo)
          analyzer.dependencies_at_commit(rugged_commit)
        end

        def get_dependencies_with_database(repo)
          ref = @options[:ref] || "HEAD"
          commit_sha = repo.rev_parse(ref)
          target_commit = Models::Commit.first(sha: commit_sha)

          return get_dependencies_stateless(repo) unless target_commit

          branch_name = repo.default_branch
          branch = Models::Branch.first(name: branch_name)
          return [] unless branch

          compute_dependencies_at_commit(target_commit, branch)
        end

        def compute_dependencies_at_commit(target_commit, branch)
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
                manifest_kind: s.manifest.kind,
                name: s.name,
                ecosystem: s.ecosystem,
                requirement: s.requirement,
                dependency_type: s.dependency_type,
                integrity: s.integrity
              }
            end
          end

          if snapshot_commit && snapshot_commit.id != target_commit.id
            commit_ids = branch.commits_dataset.select_map(Sequel[:commits][:id])
            changes = Models::DependencyChange
              .join(:commits, id: :commit_id)
              .where(Sequel[:commits][:id] => commit_ids)
              .where { Sequel[:commits][:committed_at] > snapshot_commit.committed_at }
              .where { Sequel[:commits][:committed_at] <= target_commit.committed_at }
              .order(Sequel[:commits][:committed_at])
              .eager(:manifest)
              .all

            changes.each do |change|
              key = [change.manifest.path, change.name]
              case change.change_type
              when "added", "modified"
                deps[key] = {
                  manifest_path: change.manifest.path,
                  manifest_kind: change.manifest.kind,
                  name: change.name,
                  ecosystem: change.ecosystem,
                  requirement: change.requirement,
                  dependency_type: change.dependency_type,
                  integrity: nil
                }
              when "removed"
                deps.delete(key)
              end
            end
          end

          deps.values
        end
      end
    end
  end
end
