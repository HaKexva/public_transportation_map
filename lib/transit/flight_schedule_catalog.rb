# frozen_string_literal: true

module Transit
  # Representative domestic island flights for itinerary RAPTOR.
  # Times are published-day sketches; airlines and weather change them.
  module FlightScheduleCatalog
    NOTE = "公開班次的代表時刻，實際以航空公司公告為準。"
    COLOR = "#7c3aed"

    AIRPORTS = {
      "tsa" => { name: "台北松山機場", name_en: "Taipei Songshan Airport", lat: 25.0697, lon: 121.5525 },
      "khh" => { name: "高雄小港機場", name_en: "Kaohsiung International Airport", lat: 22.5771, lon: 120.3500 },
      "rmq" => { name: "台中清泉崗機場", name_en: "Taichung Airport", lat: 24.2647, lon: 120.6206 },
      "cyi" => { name: "嘉義機場", name_en: "Chiayi Airport", lat: 23.4617, lon: 120.3925 },
      "ttt" => { name: "台東豐年機場", name_en: "Taitung Airport", lat: 22.7547, lon: 121.1017 },
      "mzg" => { name: "澎湖馬公機場", name_en: "Penghu Magong Airport", lat: 23.5687, lon: 119.6283 },
      "knh" => { name: "金門尚義機場", name_en: "Kinmen Airport", lat: 24.4279, lon: 118.3593 },
      "mfk" => { name: "馬祖南竿機場", name_en: "Matsu Nangan Airport", lat: 26.1598, lon: 119.9583 },
      "lzn" => { name: "馬祖北竿機場", name_en: "Matsu Beigan Airport", lat: 26.2242, lon: 119.9981 },
      "gni" => { name: "綠島機場", name_en: "Green Island Airport", lat: 22.6739, lon: 121.4664 },
      "kyd" => { name: "蘭嶼機場", name_en: "Orchid Island Airport", lat: 22.0270, lon: 121.5350 }
    }.freeze

    # Each route: mainland ↔ island (or island ↔ island). Trips are [depart, arrive] clocks.
    ROUTES = {
      "tsa_mzg" => {
        name: "松山－馬公",
        name_en: "Songshan–Magong",
        from: "tsa",
        to: "mzg",
        source: "台北松山－澎湖馬公國內線。#{NOTE}",
        trips: [
          { calendar: "daily", direction: "forward", times: [ "08:00", "08:55" ] },
          { calendar: "daily", direction: "forward", times: [ "12:30", "13:25" ] },
          { calendar: "daily", direction: "forward", times: [ "17:00", "17:55" ] },
          { calendar: "daily", direction: "reverse", times: [ "09:30", "10:25" ] },
          { calendar: "daily", direction: "reverse", times: [ "14:00", "14:55" ] },
          { calendar: "daily", direction: "reverse", times: [ "18:30", "19:25" ] }
        ]
      },
      "khh_mzg" => {
        name: "小港－馬公",
        name_en: "Kaohsiung–Magong",
        from: "khh",
        to: "mzg",
        source: "高雄－澎湖馬公國內線。#{NOTE}",
        trips: [
          { calendar: "daily", direction: "forward", times: [ "09:00", "09:40" ] },
          { calendar: "daily", direction: "forward", times: [ "15:30", "16:10" ] },
          { calendar: "daily", direction: "reverse", times: [ "10:20", "11:00" ] },
          { calendar: "daily", direction: "reverse", times: [ "16:50", "17:30" ] }
        ]
      },
      "rmq_mzg" => {
        name: "清泉崗－馬公",
        name_en: "Taichung–Magong",
        from: "rmq",
        to: "mzg",
        source: "台中－澎湖馬公國內線。#{NOTE}",
        trips: [
          { calendar: "daily", direction: "forward", times: [ "10:00", "10:50" ] },
          { calendar: "daily", direction: "reverse", times: [ "11:30", "12:20" ] }
        ]
      },
      "cyi_mzg" => {
        name: "嘉義－馬公",
        name_en: "Chiayi–Magong",
        from: "cyi",
        to: "mzg",
        source: "嘉義－澎湖馬公國內線。#{NOTE}",
        trips: [
          { calendar: "daily", direction: "forward", times: [ "11:00", "11:40" ] },
          { calendar: "daily", direction: "reverse", times: [ "12:20", "13:00" ] }
        ]
      },
      "tsa_knh" => {
        name: "松山－金門",
        name_en: "Songshan–Kinmen",
        from: "tsa",
        to: "knh",
        source: "台北松山－金門尚義國內線。#{NOTE}",
        trips: [
          { calendar: "daily", direction: "forward", times: [ "07:30", "08:40" ] },
          { calendar: "daily", direction: "forward", times: [ "13:00", "14:10" ] },
          { calendar: "daily", direction: "forward", times: [ "18:00", "19:10" ] },
          { calendar: "daily", direction: "reverse", times: [ "09:20", "10:30" ] },
          { calendar: "daily", direction: "reverse", times: [ "15:00", "16:10" ] },
          { calendar: "daily", direction: "reverse", times: [ "19:50", "21:00" ] }
        ]
      },
      "khh_knh" => {
        name: "小港－金門",
        name_en: "Kaohsiung–Kinmen",
        from: "khh",
        to: "knh",
        source: "高雄－金門國內線。#{NOTE}",
        trips: [
          { calendar: "daily", direction: "forward", times: [ "08:40", "09:50" ] },
          { calendar: "daily", direction: "reverse", times: [ "10:30", "11:40" ] }
        ]
      },
      "tsa_mfk" => {
        name: "松山－南竿",
        name_en: "Songshan–Nangan",
        from: "tsa",
        to: "mfk",
        source: "台北松山－馬祖南竿國內線。#{NOTE}",
        trips: [
          { calendar: "daily", direction: "forward", times: [ "08:20", "09:20" ] },
          { calendar: "daily", direction: "forward", times: [ "15:40", "16:40" ] },
          { calendar: "daily", direction: "reverse", times: [ "10:00", "11:00" ] },
          { calendar: "daily", direction: "reverse", times: [ "17:20", "18:20" ] }
        ]
      },
      "tsa_lzn" => {
        name: "松山－北竿",
        name_en: "Songshan–Beigan",
        from: "tsa",
        to: "lzn",
        source: "台北松山－馬祖北竿國內線。#{NOTE}",
        trips: [
          { calendar: "daily", direction: "forward", times: [ "09:10", "10:10" ] },
          { calendar: "daily", direction: "reverse", times: [ "10:50", "11:50" ] }
        ]
      },
      "ttt_gni" => {
        name: "台東－綠島",
        name_en: "Taitung–Green Island",
        from: "ttt",
        to: "gni",
        source: "台東－綠島國內線。#{NOTE}",
        trips: [
          { calendar: "daily", direction: "forward", times: [ "08:30", "08:50" ] },
          { calendar: "daily", direction: "forward", times: [ "14:00", "14:20" ] },
          { calendar: "daily", direction: "reverse", times: [ "09:10", "09:30" ] },
          { calendar: "daily", direction: "reverse", times: [ "14:40", "15:00" ] }
        ]
      },
      "ttt_kyd" => {
        name: "台東－蘭嶼",
        name_en: "Taitung–Orchid Island",
        from: "ttt",
        to: "kyd",
        source: "台東－蘭嶼國內線。#{NOTE}",
        trips: [
          { calendar: "daily", direction: "forward", times: [ "09:00", "09:30" ] },
          { calendar: "daily", direction: "reverse", times: [ "10:00", "10:30" ] }
        ]
      }
    }.freeze

    module_function

    def routes
      ROUTES
    end

    def airport(code)
      AIRPORTS[code.to_s]
    end

    def fetch(slug)
      ROUTES[slug.to_s]
    end
  end
end
