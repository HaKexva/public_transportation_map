# frozen_string_literal: true

module Geojson
  # TWD97 TM2 (EPSG:3826) → WGS84 for NLSC open railway shapefiles.
  module Twd97
    module_function

    def tm2_to_wgs84(x, y)
      a = 6_378_137.0
      b = 6_356_752.314_245_179
      lon0 = 121.0 * Math::PI / 180.0
      k0 = 0.9999
      dx = 250_000.0

      e = Math.sqrt(1 - (b / a)**2)
      e2 = e**2 / (1 - e**2)

      x -= dx
      m = y / k0
      mu = m / (a * (1 - e**2 / 4 - 3 * e**4 / 64 - 5 * e**6 / 256))

      e1 = (1 - Math.sqrt(1 - e**2)) / (1 + Math.sqrt(1 - e**2))
      phi1 = mu +
        (3 * e1 / 2 - 27 * e1**3 / 32) * Math.sin(2 * mu) +
        (21 * e1**2 / 16 - 55 * e1**4 / 32) * Math.sin(4 * mu) +
        (151 * e1**3 / 96) * Math.sin(6 * mu) +
        (1097 * e1**4 / 512) * Math.sin(8 * mu)

      n1 = a / Math.sqrt(1 - e**2 * Math.sin(phi1)**2)
      t1 = Math.tan(phi1)**2
      c1 = e2 * Math.cos(phi1)**2
      r1 = a * (1 - e**2) / (1 - e**2 * Math.sin(phi1)**2)**1.5
      d = x / (n1 * k0)

      lat = phi1 - (n1 * Math.tan(phi1) / r1) * (
        d**2 / 2 -
        (5 + 3 * t1 + 10 * c1 - 4 * c1**2 - 9 * e2) * d**4 / 24 +
        (61 + 90 * t1 + 298 * c1 + 45 * t1**2 - 252 * e2 - 3 * c1**2) * d**6 / 720
      )

      lon = lon0 + (
        d -
        (1 + 2 * t1 + c1) * d**3 / 6 +
        (5 - 2 * c1 + 28 * t1 - 3 * c1**2 + 8 * e2 + 24 * t1**2) * d**5 / 120
      ) / Math.cos(phi1)

      [ lon * 180 / Math::PI, lat * 180 / Math::PI ]
    end

    def project_to_wgs84(x, y)
      return [ x, y ] if x.abs <= 180 && y.abs <= 90

      tm2_to_wgs84(x, y)
    end
  end
end
