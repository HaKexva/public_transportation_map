# frozen_string_literal: true

require "fileutils"
require "json"
require "net/http"
require "uri"

module Geojson
  # Compares on-disk bus routes against Wikipedia route lists for sparse counties.
  class BusWikipediaAuditor
    Page = Data.define(:city_id, :title, :url)
    Report = Data.define(:generated_at, :pages, :gaps)

    PAGES = [
      Page.new(city_id: "MiaoliCounty", title: "苗栗縣公車", url: "https://zh.wikipedia.org/wiki/苗栗縣公車"),
      Page.new(city_id: "TaitungCounty", title: "臺東縣公車", url: "https://zh.wikipedia.org/wiki/臺東縣公車"),
      Page.new(city_id: "HualienCounty", title: "花蓮縣公車", url: "https://zh.wikipedia.org/wiki/花蓮縣公車"),
      Page.new(city_id: "YunlinCounty", title: "雲林縣市區公車", url: "https://zh.wikipedia.org/wiki/雲林縣市區公車"),
      Page.new(city_id: "Chiayi", title: "嘉義市公車", url: "https://zh.wikipedia.org/wiki/嘉義市公車"),
      Page.new(city_id: "NantouCounty", title: "南投縣公車", url: "https://zh.wikipedia.org/wiki/南投縣公車"),
      Page.new(city_id: "ChanghuaCounty", title: "彰化縣公車", url: "https://zh.wikipedia.org/wiki/彰化縣公車"),
      Page.new(city_id: "PenghuCounty", title: "澎湖縣公車", url: "https://zh.wikipedia.org/wiki/澎湖縣公車"),
      Page.new(city_id: "Hsinchu", title: "新竹市公車", url: "https://zh.wikipedia.org/wiki/新竹市公車")
    ].freeze

    def self.audit!(output_dir: nil)
      new(output_dir:).audit!
    end

    def initialize(output_dir: nil)
      @output_dir = Pathname.new(output_dir.presence || Rails.root.join("docs/bus_data_gaps"))
    end

    def audit!
      local = local_refs_by_city
      gaps = PAGES.map do |page|
        wiki_refs = fetch_wikipedia_refs(page)
        local_refs = local.fetch(page.city_id, [])
        {
          city_id: page.city_id,
          wikipedia: page.title,
          url: page.url,
          local_count: local_refs.length,
          wikipedia_count: wiki_refs.length,
          missing_locally: wiki_refs - local_refs,
          missing_on_wikipedia: local_refs - wiki_refs
        }
      end

      report = Report.new(generated_at: Time.zone.now.iso8601, pages: PAGES, gaps: gaps)
      write_report!(report)
      report
    end

    private

    def local_refs_by_city
      grouped = Hash.new { |hash, key| hash[key] = [] }

      Geojson::RoutesManifestWriter.bus_entries.each do |route|
        grouped[route["city_id"]] << normalize_ref(route["ref"])
      end
      grouped.transform_values { |refs| refs.compact.uniq.sort }
    end

    def fetch_wikipedia_refs(page)
      html = Net::HTTP.get(URI(page.url))
      refs = html.scan(/>\s*(\d+[A-Z]?)\s*</).flatten
      refs += html.scan(/>\s*([紅藍綠棕橘黃]\d+[A-Z]?)\s*</).flatten
      refs += html.scan(/>\s*([A-Z]\d+[A-Z]?)\s*</).flatten
      refs += html.scan(/\|\s*(\d+[A-Z]?)\s*\|/).flatten
      refs += html.scan(/\|\s*([紅藍綠棕橘黃]\d+[A-Z]?)\s*\|/).flatten
      refs += html.scan(/\|\s*(Y\d+)\s*\|/).flatten
      refs.map { |ref| normalize_ref(ref) }.compact.uniq.sort
    rescue StandardError
      []
    end

    def normalize_ref(ref)
      text = ref.to_s.strip
      return if text.empty?

      text.sub(/\A0+(\d)/, '\1')
    end

    def write_report!(report)
      FileUtils.mkdir_p(@output_dir)
      path = @output_dir.join("wikipedia_vs_local.md")
      lines = [
        "# Wikipedia vs local bus routes",
        "",
        "Generated at #{report.generated_at}.",
        "",
        "Sparse-county cross-check only; Wikipedia may lag or omit variants.",
        ""
      ]

      report.gaps.each do |gap|
        lines << "## #{gap[:city_id]} (#{gap[:wikipedia]})"
        lines << ""
        lines << "- Wikipedia: #{gap[:url]}"
        lines << "- Local routes: **#{gap[:local_count]}**; Wikipedia table refs scraped: **#{gap[:wikipedia_count]}**"
        lines << ""
        if gap[:missing_locally].any?
          lines << "### On Wikipedia, not in local manifest"
          lines << ""
          gap[:missing_locally].each { |ref| lines << "- `#{ref}`" }
          lines << ""
        end
        if gap[:missing_on_wikipedia].any?
          lines << "### Local only (Wikipedia may be incomplete)"
          lines << ""
          gap[:missing_on_wikipedia].first(40).each { |ref| lines << "- `#{ref}`" }
          lines << "- ..." if gap[:missing_on_wikipedia].length > 40
          lines << ""
        end
      end

      File.write(path, lines.join("\n"))
      puts "Wrote #{path}"
    end
  end
end
