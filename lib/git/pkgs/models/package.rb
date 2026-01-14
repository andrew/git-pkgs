# frozen_string_literal: true

module Git
  module Pkgs
    module Models
      class Package < Sequel::Model
        STALE_THRESHOLD = 86400 # 24 hours

        one_to_many :versions, key: :package_purl, primary_key: :purl

        dataset_module do
          def by_ecosystem(ecosystem)
            where(ecosystem: ecosystem)
          end

          def needs_vuln_sync
            where(vulns_synced_at: nil).or { vulns_synced_at < Time.now - STALE_THRESHOLD }
          end

          def synced
            where { vulns_synced_at >= Time.now - STALE_THRESHOLD }
          end

          def needs_enrichment
            where(enriched_at: nil).or { enriched_at < Time.now - STALE_THRESHOLD }
          end

          def enriched
            where { enriched_at >= Time.now - STALE_THRESHOLD }
          end
        end

        def parsed_purl
          @parsed_purl ||= Purl.parse(purl)
        end

        def registry_url
          parsed_purl.registry_url
        end

        def enriched?
          !enriched_at.nil?
        end

        def needs_enrichment?
          enriched_at.nil? || enriched_at < Time.now - STALE_THRESHOLD
        end

        def needs_vuln_sync?
          vulns_synced_at.nil? || vulns_synced_at < Time.now - STALE_THRESHOLD
        end

        def mark_vulns_synced
          update(vulns_synced_at: Time.now)
        end

        # Update package with data from ecosyste.ms API
        def enrich_from_api(data)
          supplier_name, supplier_type = extract_supplier(data)

          update(
            latest_version: data["latest_release_number"],
            license: (data["normalized_licenses"] || []).first,
            description: data["description"],
            homepage: data["homepage"],
            repository_url: data["repository_url"],
            supplier_name: supplier_name,
            supplier_type: supplier_type,
            enriched_at: Time.now
          )
        end

        # Extract supplier info from API response
        # Prefers owner_record (org), falls back to first maintainer
        def extract_supplier(data)
          owner = data["owner_record"]
          if owner && owner["name"]
            type = owner["kind"] == "organization" ? "organization" : "person"
            return [owner["name"], type]
          end

          maintainers = data["maintainers"]
          if maintainers&.any?
            first = maintainers.first
            name = first["name"] || first["login"]
            return [name, "person"] if name
          end

          [nil, nil]
        end

        def vulnerabilities
          osv_ecosystem = Ecosystems.to_osv(ecosystem)
          return [] unless osv_ecosystem

          VulnerabilityPackage
            .where(ecosystem: osv_ecosystem, package_name: name)
            .map(&:vulnerability)
            .compact
        end

        def self.find_or_create_by_purl(purl:, ecosystem: nil, name: nil)
          existing = first(purl: purl)
          return existing if existing

          create(purl: purl, ecosystem: ecosystem, name: name)
        end

        def self.generate_purl(ecosystem, name)
          Ecosystems.generate_purl(ecosystem, name)
        end
      end
    end
  end
end
