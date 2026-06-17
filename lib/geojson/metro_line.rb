# frozen_string_literal: true

module Geojson
  MetroLine = Data.define(
    :slug,
    :name,
    :name_en,
    :ref,
    :color,
    :relation_ids,
    :way_ids,
    :station_ref_prefix,
    :branch_of,
    :system_id,
    :output_subdir,
    :network_name,
    :osm_networks
  ) do
    def self.taipei(slug:, name:, name_en:, ref:, color:, relation_ids:, station_ref_prefix:, branch_of: nil, way_ids: nil)
      new(
        slug: slug,
        name: name,
        name_en: name_en,
        ref: ref,
        color: color,
        relation_ids: relation_ids,
        way_ids: way_ids || [],
        station_ref_prefix: station_ref_prefix,
        branch_of: branch_of,
        system_id: "taipei_metro",
        output_subdir: "taipei_metro",
        network_name: "臺北捷運",
        osm_networks: [ "臺北捷運", "台北捷運", "Taipei Metro" ]
      )
    end

    def self.new_taipei(slug:, name:, name_en:, ref:, color:, relation_ids:, station_ref_prefix:, branch_of: nil, way_ids: nil)
      new(
        slug: slug,
        name: name,
        name_en: name_en,
        ref: ref,
        color: color,
        relation_ids: relation_ids,
        way_ids: way_ids || [],
        station_ref_prefix: station_ref_prefix,
        branch_of: branch_of,
        system_id: "new_taipei_metro",
        output_subdir: "new_taipei_metro",
        network_name: "新北捷運",
        osm_networks: [ "新北捷運", "New Taipei Metro" ]
      )
    end

    def self.taoyuan(slug:, name:, name_en:, ref:, color:, relation_ids:, station_ref_prefix:, branch_of: nil, osm_networks: nil, way_ids: nil)
      new(
        slug: slug,
        name: name,
        name_en: name_en,
        ref: ref,
        color: color,
        relation_ids: relation_ids,
        way_ids: way_ids || [],
        station_ref_prefix: station_ref_prefix,
        branch_of: branch_of,
        system_id: "taoyuan_metro",
        output_subdir: "taoyuan_metro",
        network_name: "桃園捷運",
        osm_networks: osm_networks || [ "桃園捷運", "桃園機場捷運", "Taoyuan Metro" ]
      )
    end

    def self.taichung(slug:, name:, name_en:, ref:, color:, relation_ids:, station_ref_prefix:, branch_of: nil, osm_networks: nil, way_ids: nil)
      new(
        slug: slug,
        name: name,
        name_en: name_en,
        ref: ref,
        color: color,
        relation_ids: relation_ids,
        way_ids: way_ids || [],
        station_ref_prefix: station_ref_prefix,
        branch_of: branch_of,
        system_id: "taichung_metro",
        output_subdir: "taichung_metro",
        network_name: "臺中捷運",
        osm_networks: osm_networks || [ "臺中捷運", "台中捷運", "Taichung Metro" ]
      )
    end

    def self.kaohsiung(slug:, name:, name_en:, ref:, color:, relation_ids:, station_ref_prefix:, branch_of: nil, osm_networks: nil, way_ids: nil)
      new(
        slug: slug,
        name: name,
        name_en: name_en,
        ref: ref,
        color: color,
        relation_ids: relation_ids,
        way_ids: way_ids || [],
        station_ref_prefix: station_ref_prefix,
        branch_of: branch_of,
        system_id: "kaohsiung_metro",
        output_subdir: "kaohsiung_metro",
        network_name: "高雄捷運",
        osm_networks: osm_networks || [ "高雄捷運", "Kaohsiung Metro" ]
      )
    end

    def self.hsr(slug:, name:, name_en:, ref:, color:, relation_ids:, station_ref_prefix:, branch_of: nil, osm_networks: nil, way_ids: nil)
      new(
        slug: slug,
        name: name,
        name_en: name_en,
        ref: ref,
        color: color,
        relation_ids: relation_ids,
        way_ids: way_ids || [],
        station_ref_prefix: station_ref_prefix,
        branch_of: branch_of,
        system_id: "hsr",
        output_subdir: "hsr",
        network_name: "台灣高鐵",
        osm_networks: osm_networks || [ "台灣高鐵", "HSR", "THSR", "Taiwan High Speed Rail" ]
      )
    end

    def self.tra(slug:, name:, name_en:, ref:, color:, relation_ids:, station_ref_prefix:, branch_of: nil, osm_networks: nil, way_ids: nil)
      new(
        slug: slug,
        name: name,
        name_en: name_en,
        ref: ref,
        color: color,
        relation_ids: relation_ids,
        way_ids: way_ids || [],
        station_ref_prefix: station_ref_prefix,
        branch_of: branch_of,
        system_id: "tra",
        output_subdir: "tra",
        network_name: "台灣鐵路",
        osm_networks: osm_networks || [ "臺灣鐵路", "台灣鐵路", "Taiwan Railway", "TRA" ]
      )
    end

    def self.other(slug:, name:, name_en:, ref:, color:, station_ref_prefix:, relation_ids: nil, way_ids: nil, branch_of: nil)
      new(
        slug: slug,
        name: name,
        name_en: name_en,
        ref: ref,
        color: color,
        relation_ids: relation_ids || [],
        way_ids: way_ids || [],
        station_ref_prefix: station_ref_prefix,
        branch_of: branch_of,
        system_id: "other",
        output_subdir: "other",
        network_name: "其他",
        osm_networks: [ "其他", "Other" ]
      )
    end
  end
end
