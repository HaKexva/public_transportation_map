# frozen_string_literal: true

require "fileutils"
require "json"

module Geojson
  # Compares TDX Bus Route / Shape coverage against on-disk GeoJSON and the
  # routes.json manifest. Also lists local quality gaps (missing official map
  # URLs, thin station geometry) without calling TDX.
  class BusCoverageAuditor
    Gap = Data.define(:city_id, :route_uid, :ref, :label, :slug, :kind)
    CityReport = Data.define(
      :city_id,
      :tdx_routes,
      :tdx_with_shape,
      :expected_slugs,
      :local_slugs,
      :no_shape,
      :not_imported,
      :local_orphans
    )
    Report = Data.define(
      :generated_at,
      :cities,
      :missing_official_maps,
      :thin_geometry,
      :intercity_local_count
    )

    DEFAULT_OUTPUT_DIR = "tmp/bus_coverage"

    def self.audit!(city_ids: nil, client: nil, output_dir: nil, fetch_tdx: true)
      new(city_ids:, client:, output_dir:, fetch_tdx:).audit!
    end

    def self.export_local_gaps!(output_dir: nil)
      new(city_ids: [], client: nil, output_dir:, fetch_tdx: false).export_local_gaps!
    end

    def initialize(city_ids: nil, client: nil, output_dir: nil, fetch_tdx: true)
      @city_ids = Array(city_ids).map(&:to_s).reject(&:blank?)
      @client = client
      @output_dir = Pathname.new(output_dir.presence || Rails.root.join(DEFAULT_OUTPUT_DIR))
      @fetch_tdx = fetch_tdx
    end

    def audit!
      client = resolve_client if @fetch_tdx
      city_reports = selected_cities.map { |city| audit_city(city, client) }
      report = build_report(city_reports)
      write_reports!(report)
      report
    end

    def export_local_gaps!
      report = build_report([])
      write_local_gap_files!(report)
      report
    end

    private

    def selected_cities
      cities = Geojson::BusCatalog.cities
      return cities if @city_ids.empty?

      cities.select { |city| @city_ids.include?(city.id) }
    end

    def resolve_client
      client = @client || Transit::TdxClient.new
      if client.respond_to?(:configured?) && !client.configured?
        raise Transit::TdxClient::ConfigurationError, "TDX_CLIENT_ID and TDX_CLIENT_SECRET are required"
      end

      client
    end

    def audit_city(city, client)
      routes = client.fetch_all(Geojson::BusImporter.route_path_for(city))
      shapes = client.fetch_all(Geojson::BusImporter.shape_path_for(city))
      shaped_uids = shaped_route_uids(shapes)

      planned = Geojson::BusImporter.plan_import(routes, city: city)
      no_shape = []
      expected = []

      planned.each do |plan|
        gaps = plan[:gaps].map do |gap|
          Gap.new(
            city_id: gap[:city_id],
            route_uid: gap[:route_uid],
            ref: gap[:ref],
            label: gap[:label],
            slug: gap[:slug],
            kind: :no_shape
          )
        end

        if plan[:uids].any? { |uid| shaped_uids.include?(uid) }
          expected << plan.merge(gaps: gaps)
        else
          no_shape.concat(gaps)
        end
      end

      expected_slugs = expected.map { |plan| plan[:slug] }.uniq.sort
      local_slugs = local_slugs_for(city)
      not_imported = expected.reject { |plan| local_slugs.include?(plan[:slug]) }.flat_map do |plan|
        plan[:gaps].map { |gap| gap.with(kind: :not_imported, slug: plan[:slug]) }
      end
      local_orphans = (local_slugs - expected_slugs).map do |slug|
        Gap.new(city_id: city.id, route_uid: nil, ref: nil, label: slug, slug: slug, kind: :local_orphan)
      end

      CityReport.new(
        city_id: city.id,
        tdx_routes: routes.length,
        tdx_with_shape: shaped_uids.length,
        expected_slugs: expected_slugs,
        local_slugs: local_slugs,
        no_shape: no_shape,
        not_imported: not_imported,
        local_orphans: local_orphans
      )
    end

    def shaped_route_uids(shapes)
      Array(shapes).filter_map do |shape|
        uid = shape["RouteUID"].to_s
        next if uid.blank?

        lines = Geojson::BusImporter.parse_wkt_lines(shape["Geometry"] || shape["geometry"])
        uid if lines.any?
      end.uniq
    end

    def local_slugs_for(city)
      city_key = city.id.underscore
      sibling_prefixes = Geojson::BusCatalog.cities
        .map { |entry| entry.id.underscore }
        .reject { |key| key == city_key }
        .select { |key| key.start_with?("#{city_key}_") }

      Dir.glob(Geojson::BusLayout.bus_root.join("**/*.geojson")).filter_map do |path|
        slug = File.basename(path, ".geojson")
        next unless slug == city_key || slug.start_with?("#{city_key}_")
        next if sibling_prefixes.any? { |prefix| slug == prefix || slug.start_with?("#{prefix}_") }

        slug
      end.sort
    end

    def build_report(city_reports)
      Report.new(
        generated_at: Time.current.iso8601,
        cities: city_reports,
        missing_official_maps: missing_official_maps,
        thin_geometry: thin_geometry_gaps,
        intercity_local_count: local_slugs_for(Geojson::BusCatalog.find("InterCity")).length
      )
    end

    def missing_official_maps
      manifest_bus.select { |route| route["official_map_url"].to_s.empty? }.map do |route|
        Gap.new(
          city_id: route["city_id"],
          route_uid: nil,
          ref: route["ref"],
          label: route["name"],
          slug: route["id"],
          kind: :missing_official_map
        )
      end.sort_by { |gap| [ gap.city_id.to_s, gap.ref.to_s, gap.slug.to_s ] }
    end

    def thin_geometry_gaps
      Dir.glob(Geojson::BusLayout.bus_root.join("**/*.geojson")).filter_map do |path|
        data = JSON.parse(File.read(path))
        stations = Array(data["features"]).count { |feature| feature.dig("properties", "feature_type") == "station" }
        routes = Array(data["features"]).count { |feature| feature.dig("properties", "feature_type") == "route" }
        next unless stations < 2 || routes < 1

        props = data["properties"] || {}
        Gap.new(
          city_id: props["city_id"],
          route_uid: nil,
          ref: props["ref"],
          label: "#{props['name']} (routes=#{routes}, stations=#{stations})",
          slug: props["id"].presence || File.basename(path, ".geojson"),
          kind: :thin_geometry
        )
      rescue Errno::ENOENT, JSON::ParserError
        nil
      end.sort_by { |gap| [ gap.city_id.to_s, gap.slug.to_s ] }
    end

    def manifest_bus
      Geojson::RoutesManifestWriter.bus_entries
    end

    def write_reports!(report)
      FileUtils.mkdir_p(@output_dir)
      write_local_gap_files!(report)
      write_tdx_report!(report) if report.cities.any?
    end

    def write_local_gap_files!(report)
      FileUtils.mkdir_p(@output_dir)
      missing_path = @output_dir.join("missing_official_maps.md")
      File.write(missing_path, missing_official_markdown(report))
      puts "Wrote #{missing_path}"

      summary_path = @output_dir.join("summary.md")
      File.write(summary_path, summary_markdown(report))
      puts "Wrote #{summary_path}"
    end

    def write_tdx_report!(report)
      path = @output_dir.join("tdx_vs_local.md")
      File.write(path, tdx_markdown(report))
      puts "Wrote #{path}"

      json_path = @output_dir.join("tdx_vs_local.json")
      File.write(json_path, JSON.pretty_generate(tdx_json(report)))
      puts "Wrote #{json_path}"
    end

    def missing_official_markdown(report)
      lines = [
        "# Bus routes missing official map URL",
        "",
        "Generated at #{report.generated_at}.",
        "",
        "These routes have GeoJSON geometry but no `official_map_url` in the manifest.",
        "",
        "**Total: #{report.missing_official_maps.length}**",
        ""
      ]

      report.missing_official_maps.group_by(&:city_id).sort_by { |city, _| city.to_s }.each do |city, gaps|
        lines << "## #{city} (#{gaps.length})"
        lines << ""
        gaps.each do |gap|
          lines << "- `#{gap.ref}` #{gap.label} (`#{gap.slug}`)"
        end
        lines << ""
      end

      lines.join("\n")
    end

    def summary_markdown(report)
      lines = [
        "# Bus data coverage summary",
        "",
        "Generated at #{report.generated_at}.",
        "",
        "## Local gaps (no TDX required)",
        "",
        "- Missing official map URL: **#{report.missing_official_maps.length}**",
        "- Thin geometry: **#{report.thin_geometry.length}**",
        "- InterCity local GeoJSON files: **#{report.intercity_local_count}**",
        ""
      ]

      if report.thin_geometry.any?
        lines << "### Thin geometry"
        lines << ""
        report.thin_geometry.each do |gap|
          lines << "- `#{gap.slug}` — #{gap.label}"
        end
        lines << ""
      end

      if report.cities.any?
        lines << "## TDX vs local"
        lines << ""
        lines << "| City | TDX routes | With shape | Expected files | Local files | No shape | Not imported | Local orphans |"
        lines << "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"
        report.cities.each do |city|
          lines << [
            city.city_id,
            city.tdx_routes,
            city.tdx_with_shape,
            city.expected_slugs.length,
            city.local_slugs.length,
            city.no_shape.length,
            city.not_imported.length,
            city.local_orphans.length
          ].join(" | ").then { |row| "| #{row} |" }
        end
        lines << ""
      else
        lines << "_TDX comparison skipped (local-only export)._"
        lines << ""
      end

      lines.join("\n")
    end

    def tdx_markdown(report)
      lines = [
        "# TDX Bus Route / Shape vs local GeoJSON",
        "",
        "Generated at #{report.generated_at}.",
        ""
      ]

      report.cities.each do |city|
        lines << "## #{city.city_id}"
        lines << ""
        lines << "- TDX routes: #{city.tdx_routes}"
        lines << "- TDX routes with parseable shape: #{city.tdx_with_shape}"
        lines << "- Expected import slugs: #{city.expected_slugs.length}"
        lines << "- Local GeoJSON files: #{city.local_slugs.length}"
        lines << "- No shape (skipped): #{city.no_shape.length}"
        lines << "- Has shape, not imported: #{city.not_imported.length}"
        lines << "- Local orphans: #{city.local_orphans.length}"
        lines << ""

        append_gap_section(lines, "No shape", city.no_shape)
        append_gap_section(lines, "Has shape, not imported", city.not_imported)
        append_gap_section(lines, "Local orphans", city.local_orphans)
      end

      lines.join("\n")
    end

    def append_gap_section(lines, title, gaps)
      lines << "### #{title} (#{gaps.length})"
      lines << ""
      if gaps.empty?
        lines << "_None._"
        lines << ""
        return
      end

      gaps.first(500).each do |gap|
        parts = [ gap.label.presence || gap.slug, gap.route_uid, gap.slug ].compact
        lines << "- #{parts.join(' | ')}"
      end
      lines << "- … truncated …" if gaps.length > 500
      lines << ""
    end

    def tdx_json(report)
      {
        generated_at: report.generated_at,
        cities: report.cities.map do |city|
          {
            city_id: city.city_id,
            tdx_routes: city.tdx_routes,
            tdx_with_shape: city.tdx_with_shape,
            expected_slugs: city.expected_slugs,
            local_slugs: city.local_slugs,
            no_shape: gaps_as_json(city.no_shape),
            not_imported: gaps_as_json(city.not_imported),
            local_orphans: gaps_as_json(city.local_orphans)
          }
        end
      }
    end

    def gaps_as_json(gaps)
      gaps.map do |gap|
        {
          city_id: gap.city_id,
          route_uid: gap.route_uid,
          ref: gap.ref,
          label: gap.label,
          slug: gap.slug,
          kind: gap.kind
        }
      end
    end
  end
end
