# frozen_string_literal: true

module Geojson
  # Hand-checked corrections for TDX Shape errors (overshoots, corner cuts).
  # Each patch replaces the stretch between two existing shape vertices with a
  # road-following path (OSM geometry); `from`/`to` must be vertices of the shape.
  module BusShapePatches
    PATCHES = {
      # Plain 223 goes straight from 中華路 down the connector onto 國興路 to
      # 青年公園(國興); the 青年社宅 loop round the park is the 繞駛 variant.
      "taipei_223" => [
        {
          direction: 0,
          from: [ 121.5066148, 25.0262803 ],
          to: [ 121.5065415, 25.0259529 ],
          path: [
            [ 121.5065491, 25.0261631 ],
            [ 121.5064865, 25.0260948 ],
            [ 121.5064931, 25.0260137 ],
            [ 121.5065148, 25.0259871 ]
          ]
        }
      ],
      "taipei_20" => [
        # 松山路 → left onto 信義路六段 at the intersection, not a hairpin 20 m past it.
        {
          direction: 0,
          from: [ 121.578619, 25.035868 ],
          to: [ 121.576809, 25.035321 ],
          path: [
            [ 121.578550, 25.035936 ],
            [ 121.578490, 25.036150 ],
            [ 121.578474, 25.036275 ],
            [ 121.578402, 25.036260 ],
            [ 121.577979, 25.036153 ],
            [ 121.577915, 25.036140 ],
            [ 121.577876, 25.036109 ],
            [ 121.576864, 25.035342 ]
          ]
        }
      ],
      "taipei_33_17461a8442" => [
        # After the 永春里 loop: 福德街 out to 捷運廣慈/奉天宮站(福德) and back
        # past 信義行政中心 to 松山商職(福德).
        {
          direction: 0,
          from: [ 121.578323, 25.036278 ],
          to: [ 121.577989, 25.036193 ],
          path: [
            [ 121.579374, 25.036393 ], [ 121.580299, 25.036720 ], [ 121.582670, 25.037621 ],
            [ 121.583358, 25.037876 ], [ 121.583894, 25.038110 ], [ 121.583362, 25.037869 ],
            [ 121.582668, 25.037616 ], [ 121.580292, 25.036708 ], [ 121.579370, 25.036383 ],
            [ 121.578811, 25.036348 ]
          ]
        },
        # Down 大道路, then 福德街 out to 松山商職(福德) and back east.
        {
          direction: 1,
          from: [ 121.583933, 25.038033 ],
          to: [ 121.584135, 25.038257 ],
          path: [
            [ 121.582887, 25.037628 ], [ 121.582132, 25.037341 ], [ 121.580561, 25.036743 ],
            [ 121.579602, 25.036345 ], [ 121.578817, 25.036264 ], [ 121.578399, 25.036203 ],
            [ 121.578817, 25.036261 ], [ 121.579604, 25.036339 ], [ 121.580567, 25.036733 ],
            [ 121.582140, 25.037338 ], [ 121.582889, 25.037619 ], [ 121.583631, 25.037900 ]
          ]
        }
      ],
      # 682 at 淡水客運八里站: outbound starts ~15 m north of where inbound
      # ends, so the two Bali tips look broken. Meet at the same bay other
      # 八里站 routes use, and densify the first 八里大道 hop.
      "taipei_682" => [
        {
          direction: 0,
          exclusive_from: true,
          from: [ 121.40604304688688, 25.15361760946282 ],
          to: [ 121.40816500480503, 25.151709716162134 ],
          path: [
            [ 121.40608, 25.15348 ],
            [ 121.4063864, 25.1532347 ],
            [ 121.407295, 25.152437 ]
          ]
        },
        {
          direction: 1,
          exclusive_to: true,
          from: [ 121.40581710905522, 25.153731080843368 ],
          to: [ 121.40610378286297, 25.153485665859332 ],
          path: [
            [ 121.40608, 25.15348 ]
          ]
        }
      ],
      # 967／967直／967桃園酒廠發車: TDX chords 桃園酒廠→管理中心 across the
      # winery grounds; stay on 文化一路 (same corridor as 786).
      "new_taipei_967" => [
        {
          direction: 0,
          from: [ 121.37637457084, 25.054915190414 ],
          to: [ 121.372333028872, 25.0589927413597 ],
          path: [
            [ 121.376322, 25.054972 ], [ 121.374903, 25.056340 ], [ 121.373158, 25.058093 ]
          ]
        },
        {
          direction: 1,
          from: [ 121.373046628582, 25.0579612230641 ],
          to: [ 121.376248102687, 25.0547992965807 ],
          path: [
            [ 121.374768, 25.056241 ], [ 121.376137, 25.054896 ]
          ]
        }
      ],
      "new_taipei_967_bfe7286f44" => [
        {
          direction: 0,
          from: [ 121.37637457084, 25.054915190414 ],
          to: [ 121.372333028872, 25.0589927413597 ],
          path: [
            [ 121.376322, 25.054972 ], [ 121.374903, 25.056340 ], [ 121.373158, 25.058093 ]
          ]
        },
        {
          direction: 1,
          from: [ 121.373046628582, 25.0579612230641 ],
          to: [ 121.376187, 25.0548591 ],
          path: [
            [ 121.374768, 25.056241 ], [ 121.376137, 25.054896 ]
          ]
        }
      ],
      "new_taipei_967_962863e337" => [
        {
          direction: 0,
          from: [ 121.37637457084, 25.054915190414 ],
          to: [ 121.372333028872, 25.0589927413597 ],
          path: [
            [ 121.376322, 25.054972 ], [ 121.374903, 25.056340 ], [ 121.373158, 25.058093 ]
          ]
        },
        {
          direction: 1,
          from: [ 121.373039638334, 25.0579311913128 ],
          to: [ 121.376201550579, 25.0547976357669 ],
          path: [
            [ 121.374768, 25.056241 ], [ 121.376137, 25.054896 ]
          ]
        }
      ],
      # 紅7 at 萬金路口: TDX chords the last 延平北路八段2巷 hop, then overshoots
      # north up 153弄 past the stop before U-turning. Stay on the alley to the
      # junction, serve 萬金路口, and turn south toward 沙埔.
      "taipei_hong7" => [
        {
          direction: 0,
          from: [ 121.48818501764731, 25.10931164310749 ],
          to: [ 121.48681098496502, 25.10605592433961 ],
          path: [
            [ 121.488103, 25.109322 ], [ 121.487131, 25.109250 ], [ 121.486453, 25.109200 ],
            [ 121.486442, 25.109296 ], [ 121.486453, 25.109200 ], [ 121.486472, 25.109035 ],
            [ 121.486564, 25.108274 ], [ 121.486573, 25.108197 ], [ 121.486591, 25.108034 ],
            [ 121.486658, 25.107438 ], [ 121.486717, 25.106674 ], [ 121.486743, 25.106495 ],
            [ 121.486778, 25.106286 ]
          ]
        }
      ],
      # 990 outbound: after the 捷運淡水站 terminal loop TDX chords NW across
      # the plaza to 中正東路; follow the road out toward 重建街口.
      "new_taipei_990" => [
        {
          direction: 0,
          from: [ 121.447191, 25.1676288 ],
          to: [ 121.4450734, 25.1688028 ],
          path: [
            [ 121.447073, 25.167697 ], [ 121.446680, 25.167921 ], [ 121.446076, 25.168222 ],
            [ 121.445663, 25.168438 ], [ 121.445282, 25.168639 ]
          ]
        }
      ],
      # 615 ends at 臺大醫院 on the southbound carriageway of 中山南路, then turns
      # onto 徐州路 toward 開南中學. TDX chords across the hospital block and
      # sends the return down 公園路 before jumping east.
      "taipei_615" => [
        {
          direction: 0,
          from: [ 121.51916834841846, 25.04469562794997 ],
          to: [ 121.51851298930704, 25.042415638989244 ],
          exclusive_to: true,
          path: [
            [ 121.519150, 25.044550 ], [ 121.519120, 25.044450 ], [ 121.519060, 25.044270 ],
            [ 121.518940, 25.043840 ], [ 121.518900, 25.043720 ], [ 121.518830, 25.043480 ],
            [ 121.518790, 25.043350 ], [ 121.518860, 25.043130 ], [ 121.518655, 25.042420 ]
          ]
        },
        {
          direction: 1,
          from: [ 121.518585469085, 25.042634526437475 ],
          to: [ 121.5186027121637, 25.04173151965815 ],
          exclusive_from: true,
          path: [
            [ 121.518655, 25.042420 ], [ 121.518560, 25.042090 ], [ 121.518540, 25.042030 ],
            [ 121.518500, 25.041910 ]
          ]
        },
        {
          direction: 1,
          from: [ 121.51874824561705, 25.04180876365537 ],
          to: [ 121.5221942393795, 25.040981253026267 ],
          path: [
            [ 121.518980, 25.041800 ], [ 121.519260, 25.041730 ], [ 121.519530, 25.041670 ],
            [ 121.519830, 25.041590 ], [ 121.520240, 25.041500 ], [ 121.520530, 25.041430 ],
            [ 121.521170, 25.041280 ], [ 121.522020, 25.041070 ]
          ]
        }
      ],
      # 紅68繞駛: TDX shares the plain shape and chords past 遠雄商舟大樓;
      # densify 福美承平→中鼎 along 承平路 via the building stop.
      "taipei_hong68_e18a6107ef" => [
        {
          direction: 0,
          from: [ 121.5080775, 25.1004889 ],
          to: [ 121.5097909, 25.1005325 ],
          path: [
            [ 121.508546, 25.100512 ],
            [ 121.508998, 25.100517 ], # 遠雄商舟大樓
            [ 121.509500, 25.100525 ]
          ]
        }
      ]
    }.freeze
    # TDX parks 615's outbound 臺大醫院 pole inside the block, west of 中山南路.
    STOP_MOVES = {
      "taipei_615" => [
        { direction: 0, name: "臺大醫院", coordinates: [ 121.518655, 25.042420 ] },
        { direction: 1, name: "臺大醫院", coordinates: [ 121.518687, 25.041809 ] }
      ]
    }.freeze
    VERTEX_MATCH_METERS = 3.0

    # Shapes that include a detour only some trips run: everything between the
    # first and last pass of `anchor` (the junction where the detour leaves
    # the plain route) is dropped.
    EXCURSIONS = {
      # 永春里／大道路 loop is the 繞駛 variant; plain 33 stays on 福德街.
      "taipei_33" => [
        { direction: 0, anchor: [ 121.583855, 25.038199 ] }, # 福德街／大道路
        { direction: 1, anchor: [ 121.578410, 25.036250 ] }  # 福德街／松山路
      ]
    }.freeze
    # Out-and-back spurs only a variant runs. The plain route leaves `leave`,
    # reaches `tip`, and comes back to `leave`; that stretch is dropped.
    SPURS = {
      # 237本線 turns at 政大一. 延駛政大校區 is the trip that continues to 政大圖書館.
      "taipei_237" => [
        { direction: 0, leave: [ 121.576044, 24.987821 ], tip: [ 121.576910, 24.986166 ], stop: "政大圖書館" }
      ],
      # 963 直達已併正線：TDX 仍殘留過五府千歲後上成泰路高架再折回的支線。
      # 正線改經五股服務社、由中興路上高架。
      "new_taipei_963" => [
        { direction: 0, leave: [ 121.4488033, 25.0958009 ], tip: [ 121.4477302, 25.0861966 ] }, # 西雲寺 ↔ 成泰高架
        { direction: 1, leave: [ 121.4517088, 25.1007666 ], tip: [ 121.447948, 25.0845435 ] } # 五股郵局 ↔ 成泰高架
      ]
    }.freeze
    # Drop a wrong prefix before the true outbound terminal. 508區's TDX shape
    # starts at 蘆洲站, runs up to 蘆洲總站, then turns back onto the real path.
    START_TRIMS = {
      "taipei_508sh" => [
        { direction: 0, at: [ 121.465886, 25.089076 ] } # 蘆洲總站
      ],
      # 712's TDX shape keeps a 貴興路 tip past 捷運亞東醫院站 so dir0/dir1 join;
      # passenger service ends at the hospital stop.
      "new_taipei_712" => [
        { direction: 1, at: [ 121.452517, 24.998579 ] } # 捷運亞東醫院站
      ]
    }.freeze
    # Drop a deadhead / layover tip after the last passenger stop.
    END_TRIMS = {
      "new_taipei_712" => [
        { direction: 0, at: [ 121.453027, 24.999426 ] } # 捷運亞東醫院站
      ]
    }.freeze
    START_TRIM_METERS = 40.0
    END_TRIM_METERS = 200.0
    TERMINUS_AT_METERS = 40.0
    # Rewrite a terminus approach: keep the line through `at`, then follow `path`
    # (`:end`), or prefix `path` and resume from `at` (`:start`). Used when TDX
    # cuts the fold-back as a chord and the return line skips the first stop.
    TERMINUS_REWRITES = {
      # 589 at 南港車站: TDX cuts north from the bay to 南港路, then the return
      # jumps east past 南港行政中心. Exit the bay, join 南港路 by the admin
      # centre, and start the return from there (same path 590 uses).
      "new_taipei_589" => [
        {
          direction: 0,
          side: :end,
          at: [ 121.6064266, 25.0533602 ],
          path: [
            [ 121.606380, 25.053520 ], [ 121.606330, 25.053720 ], [ 121.606280, 25.053920 ],
            [ 121.606250, 25.054110 ], [ 121.606247, 25.054138 ], [ 121.606252, 25.054166 ],
            [ 121.606263, 25.054192 ], [ 121.606281, 25.054216 ], [ 121.606304, 25.054235 ],
            [ 121.606331, 25.054248 ], [ 121.606360, 25.054256 ], [ 121.606686, 25.054306 ]
          ]
        },
        {
          direction: 1,
          side: :start,
          at: [ 121.609262, 25.054780 ],
          path: [
            [ 121.606686, 25.054306 ], [ 121.607120, 25.054330 ], [ 121.607800, 25.054480 ],
            [ 121.608626, 25.054647 ], [ 121.609262, 25.054780 ]
          ]
        }
      ]
    }.freeze
    # 紅5: after 捷運劍潭站(北藝中心), continue south on 劍潭路 to 基河路,
    # U-turn, then back to the 北藝 boarding tip where inbound starts.
    HONG5_JIANTAN_TURNAROUND = {
      direction: 0,
      from: [ 121.5249684, 25.0849035 ],
      path: [
        [ 121.52512, 25.08470 ], [ 121.525321, 25.084329 ], [ 121.525314, 25.084299 ],
        [ 121.525298, 25.084272 ], [ 121.525275, 25.084251 ], [ 121.525246, 25.084236 ],
        [ 121.525214, 25.084229 ], [ 121.525181, 25.084230 ], [ 121.524974, 25.084264 ],
        [ 121.524945, 25.084272 ], [ 121.524919, 25.084286 ], [ 121.524897, 25.084305 ],
        [ 121.524881, 25.084329 ], [ 121.524870, 25.084355 ], [ 121.524867, 25.084382 ],
        [ 121.524871, 25.084409 ], [ 121.525010, 25.084937 ]
      ]
    }.freeze
    # Short-turn turnarounds: TDX ends the outbound at the terminal stop and
    # starts the inbound farther along the return. Append the road path so the
    # map keeps following the bus after the last outbound stop.
    TURNAROUNDS = {
      # Path-pair slugs: 本線 / 繞駛文化大學 (both end at the same tip).
      "taipei_hong5_2441bedf1c" => [ HONG5_JIANTAN_TURNAROUND ],
      "taipei_hong5_312257b87e" => [ HONG5_JIANTAN_TURNAROUND ],
      # 紅55區: after 臺北城市科技大學, reverse back to 學園路口 (inbound boards there).
      # reuse_outbound: path retraces the approach, so mid-path points are already
      # on the line before the patch — idempotency keys off path.last instead.
      "taipei_hong55sh" => [
        {
          direction: 0,
          reuse_outbound: true,
          from: [ 121.468095, 25.132855 ],
          path: [
            [ 121.468095, 25.132855 ], [ 121.468116, 25.132867 ], [ 121.468161, 25.132901 ],
            [ 121.468191, 25.132912 ], [ 121.468209, 25.132900 ], [ 121.468216, 25.132872 ],
            [ 121.468145, 25.132801 ], [ 121.468053, 25.132714 ], [ 121.468035, 25.132698 ],
            [ 121.468003, 25.132676 ], [ 121.467967, 25.132662 ], [ 121.467948, 25.132658 ],
            [ 121.467929, 25.132659 ], [ 121.467910, 25.132663 ], [ 121.467893, 25.132670 ],
            [ 121.467823, 25.132708 ], [ 121.467574, 25.132839 ], [ 121.467474, 25.132878 ],
            [ 121.467366, 25.132899 ], [ 121.467321, 25.132904 ], [ 121.467197, 25.132906 ],
            [ 121.467184, 25.132905 ], [ 121.467136, 25.132898 ], [ 121.467089, 25.132884 ],
            [ 121.467046, 25.132864 ], [ 121.467008, 25.132836 ], [ 121.466974, 25.132805 ],
            [ 121.466846, 25.132673 ], [ 121.466644, 25.132430 ], [ 121.466398, 25.132130 ],
            [ 121.466237, 25.131890 ], [ 121.466231, 25.131879 ], [ 121.466119, 25.131641 ],
            [ 121.466097, 25.131587 ], [ 121.466047, 25.131451 ], [ 121.466019, 25.131310 ],
            [ 121.466011, 25.131226 ], [ 121.465992, 25.130915 ], [ 121.465976, 25.130362 ],
            [ 121.465987, 25.130111 ], [ 121.466001, 25.129986 ], [ 121.466017, 25.129825 ],
            [ 121.466033, 25.129500 ], [ 121.466035, 25.129298 ], [ 121.466019, 25.129173 ],
            [ 121.466001, 25.129111 ], [ 121.465833, 25.128582 ], [ 121.465745, 25.128260 ],
            [ 121.465642, 25.127810 ], [ 121.465624, 25.127710 ], [ 121.465611, 25.127583 ],
            [ 121.465618, 25.127456 ], [ 121.465624, 25.127419 ], [ 121.465658, 25.127239 ]
          ]
        }
      ],
      # 311區: after 水源市場, south through 公館路口 then 福和橋 back to 林森路
      # where the inbound shape resumes at 福和橋(林森路).
      "taipei_311sh" => [
        {
          direction: 0,
          from: [ 121.535856, 25.013166 ],
          path: [
            [ 121.5358405, 25.0131552 ], [ 121.5359906, 25.0129759 ], [ 121.5360074, 25.0129568 ],
            [ 121.5362576, 25.01258 ], [ 121.5364656, 25.0122256 ], [ 121.5365581, 25.0120579 ],
            [ 121.5366486, 25.0118902 ], [ 121.5365506, 25.011848 ], [ 121.5362101, 25.0116823 ],
            [ 121.5359943, 25.0115773 ], [ 121.5359398, 25.0115528 ], [ 121.535976, 25.0114905 ],
            [ 121.535994, 25.0114595 ], [ 121.5360348, 25.0113893 ], [ 121.5362094, 25.0110914 ],
            [ 121.5362419, 25.0110477 ], [ 121.5361977, 25.0110387 ], [ 121.5361574, 25.0110295 ],
            [ 121.5359467, 25.0109817 ], [ 121.5357578, 25.0109091 ], [ 121.5354925, 25.0107709 ],
            [ 121.5352534, 25.01064 ], [ 121.5349818, 25.0104814 ], [ 121.534542, 25.0101726 ],
            [ 121.5340908, 25.0098553 ], [ 121.5319758, 25.0086711 ], [ 121.5307679, 25.0079919 ],
            [ 121.5295805, 25.0072858 ], [ 121.5273929, 25.006032 ], [ 121.5264488, 25.0054924 ],
            [ 121.5250743, 25.004679 ], [ 121.5242372, 25.0041863 ], [ 121.52403, 25.0040587 ],
            [ 121.5235079, 25.0037646 ]
          ]
        }
      ],
      # 672區: after 捷運公館站, the bus lane up 羅斯福路, north on 新生南路,
      # east on 辛亥路, then south on 基隆路 to where the return starts.
      "taipei_672sh" => [
        {
          direction: 0,
          from: [ 121.535179, 25.013984 ],
          path: [
            [ 121.535185, 25.013993 ], [ 121.5351292, 25.0139918 ], [ 121.534947, 25.0142124 ],
            [ 121.5343492, 25.0147807 ], [ 121.5340159, 25.0150884 ], [ 121.53391, 25.0152172 ],
            [ 121.5336089, 25.0155016 ], [ 121.532966, 25.0161237 ], [ 121.5329112, 25.016178 ],
            [ 121.5327708, 25.0163548 ], [ 121.5330061, 25.0165445 ], [ 121.5332206, 25.0167284 ],
            [ 121.5332837, 25.0167871 ], [ 121.5333319, 25.0168493 ], [ 121.5333584, 25.0168931 ],
            [ 121.5333896, 25.016952 ], [ 121.5334095, 25.0170055 ], [ 121.5334734, 25.0173497 ],
            [ 121.5336075, 25.018013 ], [ 121.5336824, 25.018363 ], [ 121.533742, 25.0186474 ],
            [ 121.5337556, 25.0187124 ], [ 121.5338449, 25.0191473 ], [ 121.5338551, 25.019197 ],
            [ 121.5340974, 25.0203768 ], [ 121.5341095, 25.0204356 ], [ 121.5341982, 25.0208673 ],
            [ 121.5342282, 25.0210132 ], [ 121.5343496, 25.0216039 ], [ 121.5343895, 25.021798 ],
            [ 121.5344444, 25.022066 ], [ 121.5344809, 25.0222441 ], [ 121.5346322, 25.0222464 ],
            [ 121.5353167, 25.0222478 ], [ 121.5358074, 25.0222582 ], [ 121.5361462, 25.0222645 ],
            [ 121.5364116, 25.0222694 ], [ 121.5366979, 25.0222821 ], [ 121.5369072, 25.0222686 ],
            [ 121.5371137, 25.0222391 ], [ 121.5373155, 25.0221899 ], [ 121.5374117, 25.0221546 ],
            [ 121.5374729, 25.0221322 ], [ 121.5375139, 25.0221172 ], [ 121.5376943, 25.0220359 ],
            [ 121.5378632, 25.0219307 ], [ 121.5379535, 25.0218669 ], [ 121.5380321, 25.021813 ],
            [ 121.5380723, 25.0217854 ], [ 121.5381499, 25.0217031 ], [ 121.5382458, 25.0216393 ],
            [ 121.5383367, 25.0215827 ], [ 121.538459, 25.0215093 ], [ 121.5385869, 25.021443 ],
            [ 121.5387037, 25.0213841 ], [ 121.5388237, 25.02133 ], [ 121.5390329, 25.0212601 ],
            [ 121.5392682, 25.0212054 ], [ 121.5393727, 25.0211811 ], [ 121.5395297, 25.0211586 ],
            [ 121.5397009, 25.0211496 ], [ 121.5408522, 25.021116 ], [ 121.5411566, 25.0211071 ],
            [ 121.5412359, 25.0211048 ], [ 121.541765, 25.0210878 ], [ 121.5418241, 25.0210859 ],
            [ 121.5430737, 25.0210457 ], [ 121.5431336, 25.0210437 ], [ 121.5431965, 25.0210417 ],
            [ 121.54329, 25.0210394 ], [ 121.5433524, 25.0210388 ], [ 121.5434068, 25.0210372 ],
            [ 121.5434646, 25.0210374 ], [ 121.5436538, 25.0210268 ], [ 121.5438626, 25.0209993 ],
            [ 121.5440903, 25.0209475 ], [ 121.5442787, 25.0208883 ], [ 121.5444483, 25.0208296 ],
            [ 121.5446194, 25.0207364 ], [ 121.5447353, 25.0206643 ], [ 121.5449794, 25.0204517 ],
            [ 121.5452949, 25.0201448 ], [ 121.5454523, 25.0199918 ], [ 121.5456196, 25.0198291 ],
            [ 121.5460647, 25.0193962 ], [ 121.546122, 25.0193456 ], [ 121.5461909, 25.0192849 ],
            [ 121.5462758, 25.0192036 ], [ 121.5463388, 25.0191501 ], [ 121.5463845, 25.0191113 ],
            [ 121.5463052, 25.0190502 ], [ 121.546285, 25.0190253 ], [ 121.5461044, 25.0188756 ],
            [ 121.5456996, 25.0185458 ], [ 121.5456464, 25.0185024 ]
          ]
        }
      ]
    }.freeze
    # Short-turns that should keep following the main-line return after the
    # last outbound stop. Path is sliced from the sibling route's inbound.
    SIBLING_TURNAROUNDS = {
      # 953區: after 臺北科技大學(忠孝), continue like 953 inbound to 富景天下
      # where the short-turn return shape resumes.
      "new_taipei_953sh" => [
        {
          direction: 0,
          from: [ 121.53442, 25.04202 ],
          sibling_id: "new_taipei_953",
          sibling_direction: 1,
          until: [ 121.72612, 25.11655 ]
        }
      ]
    }.freeze
    TURNAROUND_FROM_METERS = 40.0
    SIBLING_TURNAROUND_SNAP_METERS = 120.0
    SPUR_LEAVE_METERS = 25.0
    SPUR_TIP_METERS = 40.0
    MIN_SPUR_METERS = 80.0
    SPUR_STOP_METERS = 40.0
    EXCURSION_ANCHOR_METERS = 30.0
    MIN_EXCURSION_METERS = 300.0

    # Off-street stops where every route runs the same internal circulation.
    # A route's visit (the part of its line inside `bounds`, passing the stop)
    # is replaced by the path for the side it enters from; `west_of` splits
    # the entry sides. Visits that do not return to the west side are left alone.
    TRI_SERVICE_LOOP = [
      # 西迴一樓: north-east along the south drive, round the platform, out north-west.
      [ 121.591995, 25.071488 ], [ 121.592098, 25.071542 ], [ 121.592151, 25.071600 ],
      [ 121.592175, 25.071628 ], [ 121.592208, 25.071690 ], [ 121.592226, 25.071757 ],
      [ 121.592228, 25.071827 ], [ 121.592214, 25.071895 ], [ 121.592185, 25.071959 ],
      [ 121.592160, 25.071992 ], [ 121.592128, 25.072022 ], [ 121.592017, 25.072119 ],
      [ 121.591600, 25.072366 ], [ 121.591549, 25.072396 ],
      # Back down to the exit drive and west to 成功路.
      [ 121.591237, 25.072178 ], [ 121.591041, 25.072041 ], [ 121.591016, 25.071951 ],
      [ 121.590901, 25.071965 ], [ 121.590261, 25.071981 ]
    ].freeze
    STOP_CIRCULATIONS = {
      "三總內湖站" => {
        bounds: [ 121.5900, 25.0706, 121.5927, 25.0728 ],
        west_of: 121.5900,
        max_stop_meters: 60.0,
        paths: {
          # From 成功路 along the entry drive.
          west: [
            [ 121.590254, 25.071701 ], [ 121.590893, 25.071686 ], [ 121.591009, 25.071693 ],
            [ 121.591036, 25.071584 ], [ 121.591202, 25.071458 ], [ 121.591516, 25.071221 ]
          ] + TRI_SERVICE_LOOP,
          # From the east along the south service road, then up the one-way alley.
          east: [
            [ 121.592196, 25.070866 ], [ 121.592127, 25.070870 ], [ 121.592082, 25.070872 ],
            [ 121.591977, 25.070903 ]
          ] + TRI_SERVICE_LOOP
        }
      }
    }.freeze
    # Terminals where the joined line cuts straight from the arrival stop to the
    # departure stop: a line ending at `departure` right after a vertex near
    # `arrival` gets that last hop redrawn along `path` (the terminal lane).
    TERMINAL_APPROACHES = [
      {
        # 萬芳社區: from 萬美街 south through the bus lot to the 萬安街 side.
        name: "萬芳社區",
        arrival: [ 121.569816, 25.002253 ],
        departure: [ 121.570457, 25.001753 ],
        arrival_meters: 30.0,
        departure_meters: 15.0,
        path: [
          [ 121.569899, 25.002318 ], [ 121.569898, 25.002252 ], [ 121.569897, 25.001831 ], [ 121.570450, 25.001830 ]
        ]
      }
    ].freeze
    # Off-street terminal loops: a line ending (starting) at `stop` has its
    # stretch from the first (to the last) vertex within `join_meters` of the
    # street junction replaced by the `arrival` (`departure`) half of the loop.
    TERMINAL_LOOPS = [
      {
        # 陽明山國家公園管理處 (第二停車場): one-way off 竹子湖路 south-west to
        # the lot, round past the terminus, back north-east to 竹子湖路.
        name: "陽明山國家公園管理處",
        stop: [ 121.544693, 25.153887 ],
        stop_meters: 30.0,
        join_meters: 30.0,
        arrival: [
          [ 121.545928, 25.155456 ], [ 121.545800, 25.155369 ], [ 121.545747, 25.155312 ], [ 121.545679, 25.155243 ],
          [ 121.545625, 25.155189 ], [ 121.545593, 25.155158 ], [ 121.545473, 25.155046 ], [ 121.545433, 25.155004 ],
          [ 121.545336, 25.154908 ], [ 121.545084, 25.154644 ], [ 121.544960, 25.154576 ], [ 121.544793, 25.154397 ],
          [ 121.544699, 25.154309 ], [ 121.544591, 25.154181 ], [ 121.544560, 25.154118 ], [ 121.544594, 25.154074 ],
          [ 121.544753, 25.153999 ]
        ],
        departure: [
          [ 121.544753, 25.153999 ], [ 121.545071, 25.153850 ], [ 121.545200, 25.153829 ], [ 121.545353, 25.153909 ],
          [ 121.545413, 25.153979 ], [ 121.545461, 25.154082 ], [ 121.545605, 25.154409 ], [ 121.545743, 25.154735 ],
          [ 121.545870, 25.155029 ], [ 121.545887, 25.155065 ], [ 121.545905, 25.155098 ], [ 121.545956, 25.155146 ],
          [ 121.546007, 25.155183 ], [ 121.546108, 25.155257 ]
        ]
      },
      {
        # 天母: up 中山北路七段 (northbound side) past the drop-off, once round
        # 天母圓環 counter-clockwise, back down the southbound side to the
        # boarding stop. TDX ends both directions at one point by the east kerb;
        # the small stop_meters keeps a re-run from matching the patched ends.
        name: "天母",
        stop: [ 121.532700785386, 25.1243016019796 ],
        stop_meters: 8.0,
        join_meters: 30.0,
        arrival: [
          [ 121.532713, 25.1244508 ], [ 121.5327569, 25.1245677 ], [ 121.5327992, 25.1245685 ], [ 121.53284, 25.1245784 ],
          [ 121.532877, 25.1245969 ], [ 121.5329081, 25.1246229 ], [ 121.5329314, 25.1246549 ], [ 121.5329455, 25.124691 ],
          [ 121.5329497, 25.124729 ], [ 121.5329438, 25.1247669 ], [ 121.5329279, 25.1248024 ], [ 121.5329032, 25.1248335 ],
          [ 121.532871, 25.1248583 ], [ 121.5328331, 25.1248753 ], [ 121.5327919, 25.1248837 ], [ 121.5327496, 25.1248829 ],
          [ 121.5327088, 25.124873 ], [ 121.5326717, 25.1248545 ], [ 121.5326407, 25.1248285 ], [ 121.5326174, 25.1247965 ],
          [ 121.5326032, 25.1247605 ], [ 121.532599, 25.1247224 ], [ 121.532605, 25.1246845 ], [ 121.5326208, 25.124649 ],
          [ 121.5326456, 25.1246179 ], [ 121.5326778, 25.1245932 ], [ 121.5326382, 25.1244929 ], [ 121.5326326, 25.1244787 ],
          [ 121.532527, 25.12420 ]
        ],
        departure: [
          [ 121.532527, 25.12420 ], [ 121.5324218, 25.1239219 ], [ 121.532272341459, 25.1235273321679 ]
        ]
      }
    ].freeze
    SPIKE_RADIUS_METERS = 400.0
    LOOP_SNAP_METERS = 25.0

    # Neighbourhood street loops whose TDX shapes cut every corner differently.
    # The stretch of a route lying within `max_meters` of the loop is redrawn
    # along the loop from where it joins to where it leaves, in whichever
    # direction fits the original shape best (ties go the listed way round).
    # `loop` is closed and listed in the usual direction of travel (OSM roads).
    LOOP_CIRCULATIONS = [
      {
        # 南港花園社區: 福德街373巷 north past 花二, 福德街 over the top and down
        # past 花一／花五, then 福德街373巷 back past 花四／花三.
        name: "南港花園社區",
        max_meters: 60.0,
        # 成福路269巷 (south-west), 福德街 from the west, 東新街170巷 (north-east).
        junctions: [ [ 121.591642, 25.038727 ], [ 121.590613, 25.040366 ], [ 121.592897, 25.040417 ] ],
        loop: [
          [ 121.591642, 25.038727 ], [ 121.591580, 25.038753 ], [ 121.591496, 25.038788 ], [ 121.591423, 25.038866 ],
          [ 121.591370, 25.038941 ], [ 121.591329, 25.039071 ], [ 121.591296, 25.039322 ], [ 121.591282, 25.039365 ],
          [ 121.591214, 25.039579 ], [ 121.591096, 25.039928 ], [ 121.591069, 25.040023 ], [ 121.590956, 25.040148 ],
          [ 121.590707, 25.040306 ], [ 121.590613, 25.040366 ], [ 121.590632, 25.040415 ], [ 121.590683, 25.040545 ],
          [ 121.590747, 25.041108 ], [ 121.590792, 25.041217 ], [ 121.590860, 25.041290 ], [ 121.590984, 25.041329 ],
          [ 121.591012, 25.041334 ], [ 121.591124, 25.041352 ], [ 121.591381, 25.041334 ], [ 121.591493, 25.041303 ],
          [ 121.591559, 25.041257 ], [ 121.591631, 25.041155 ], [ 121.591770, 25.040845 ], [ 121.591940, 25.040333 ],
          [ 121.592020, 25.040154 ], [ 121.592135, 25.040043 ], [ 121.592242, 25.040005 ], [ 121.592352, 25.039995 ],
          [ 121.592508, 25.040047 ], [ 121.592607, 25.040104 ], [ 121.592679, 25.040155 ], [ 121.592782, 25.040264 ],
          [ 121.592855, 25.040361 ], [ 121.592897, 25.040417 ], [ 121.592994, 25.040312 ], [ 121.593430, 25.039842 ],
          [ 121.593467, 25.039800 ], [ 121.593483, 25.039712 ], [ 121.593483, 25.039511 ], [ 121.593485, 25.039251 ],
          [ 121.593457, 25.039137 ], [ 121.593382, 25.039043 ], [ 121.593287, 25.038967 ], [ 121.593156, 25.038890 ],
          [ 121.593034, 25.038858 ], [ 121.592533, 25.038808 ], [ 121.591728, 25.038735 ], [ 121.591642, 25.038727 ]
        ]
      }
    ].freeze

    # 249本線 returns via 崁頂、螢橋國小 and 重慶南路. TDX publishes that stop
    # list on the subroute it calls 249繞崁頂, and the plain subroute drives
    # the same loop without the stops. The plain path stays south of 螢橋.
    KANDING_MAIN_ID = "new_taipei_249"
    KANDING_SKIP_ID = "new_taipei_249_abd7b4b06a"
    KANDING_TIP = [ 121.5148181, 25.02600956 ].freeze
    KANDING_LEAVE = [ 121.512093243214, 25.0241437032268 ].freeze
    KANDING_BACK = [ 121.515439391232, 25.020491139693 ].freeze
    KANDING_TIP_METERS = 40.0
    KANDING_JOIN_METERS = 25.0
    KANDING_STOP_METERS = 40.0
    KANDING_DIRECT = [
      [ 121.512317297334, 25.0241480811012 ],
      [ 121.514922053098, 25.0239036944121 ],
      [ 121.515380149563, 25.0237418062886 ],
      [ 121.515957902468, 25.0233535094127 ],
      [ 121.516117444387, 25.0230942537946 ],
      [ 121.51620425396, 25.022700091407 ],
      [ 121.516206600165, 25.0225077026226 ],
      [ 121.516199561551, 25.0223634110342 ],
      [ 121.516140906433, 25.0221510795099 ],
      [ 121.515817130186, 25.0215938558965 ],
      [ 121.515556701466, 25.0209533420166 ]
    ].freeze
    # 260區經花鐘 is on the published 260區 board (陽明山總站 out to 第一停車場(花鐘)
    # and back). The imported stop list skips that out-and-back; the shape still drives it.
    FLOWER_ROUTE_ID = "taipei_260sh"
    FLOWER_POINT = [ 121.539696, 25.157244 ].freeze
    FLOWER_METERS = 40.0
    FLOWER_DIRECTIONS = {
      "0" => {
        anchor: "陽明山",
        place: :before,
        stops: [
          { name: "頂坪", name_en: "Dingping", ref: "TPE152728", station_id: "20372",
            coordinates: [ 121.5393511, 25.152848 ] },
          { name: "陽明山立體停車場(草山行館)", name_en: "Yangmingshan Car Park (Grass Mountain Residence)",
            ref: "TPE151093", station_id: "1165606596", coordinates: [ 121.539219, 25.15468 ] },
          { name: "第一停車場(花鐘)", name_en: "Parking Lot 1 (Flower Clock)", ref: "TPE1129100700",
            station_id: "1129100700", coordinates: [ 121.539696, 25.157244 ] },
          { name: "陽明山立體停車場(草山行館)", name_en: "Yangmingshan Car Park (Grass Mountain Residence)",
            ref: "TPE184109", station_id: "1165606595", coordinates: [ 121.5390768, 25.154665 ] },
          { name: "頂坪", name_en: "Dingping", ref: "TPE152732", station_id: "20371",
            coordinates: [ 121.539832, 25.15232 ] },
          { name: "橫嶺古道", name_en: "Hengling Historic Trail", ref: "TPE186833", station_id: "1165603368",
            coordinates: [ 121.54109, 25.151749 ] },
          { name: "第二接續井", name_en: "Second Contiunation Well", ref: "TPE211060", station_id: "1165608405",
            coordinates: [ 121.544346, 25.151846 ] }
        ]
      },
      "1" => {
        anchor: "陽明山",
        place: :after,
        stops: [
          { name: "頂坪", name_en: "Dingping", ref: "TPE152728", station_id: "20372",
            coordinates: [ 121.5393511, 25.152848 ] },
          { name: "陽明山立體停車場(草山行館)", name_en: "Yangmingshan Car Park (Grass Mountain Residence)",
            ref: "TPE151093", station_id: "1165606596", coordinates: [ 121.539219, 25.15468 ] },
          { name: "第一停車場(花鐘)", name_en: "Parking Lot 1 (Flower Clock)", ref: "TPE1129100700",
            station_id: "1129100700", coordinates: [ 121.539696, 25.157244 ] },
          { name: "陽明山立體停車場(草山行館)", name_en: "Yangmingshan Car Park (Grass Mountain Residence)",
            ref: "TPE184109", station_id: "1165606595", coordinates: [ 121.5390768, 25.154665 ] },
          { name: "頂坪", name_en: "Dingping", ref: "TPE152732", station_id: "20371",
            coordinates: [ 121.539832, 25.15232 ] },
          { name: "橫嶺古道", name_en: "Hengling Historic Trail", ref: "TPE186833", station_id: "1165603368",
            coordinates: [ 121.54109, 25.151749 ] }
        ]
      }
    }.freeze

    # 公館圓環 (羅斯福路／基隆路) was removed in 2025. A shape that still
    # circulates that ring is pulled back onto the roads through the junction.
    GONGGUAN_CENTER = [ 121.53715, 25.01115 ].freeze
    GONGGUAN_NEAR_METERS = 95.0
    GONGGUAN_ANCHOR_METERS = 180.0
    GONGGUAN_EXTRA_METERS = 16.0
    GONGGUAN_OFF_METERS = 15.0
    GONGGUAN_DETOUR_METERS = 120.0

    KANDING_STOPS = [
      { name: "崁頂", name_en: "Kanding", ref: "NWT218643", station_id: "1779",
        coordinates: [ 121.513072, 25.02502148 ] },
      { name: "螢橋國小", name_en: "Yingqiao Elementary School", ref: "NWT218644", station_id: "2018",
        coordinates: [ 121.5148181, 25.02600956 ] },
      { name: "重慶南路三段(中正橋)", name_en: "Chongqing S. Road Sec. 3 (Zhongzheng Bridge)", ref: "NWT218645",
        station_id: "1920", coordinates: [ 121.516528, 25.024804 ] }
    ].freeze

    module_function

    def process_collection!(data, router: nil)
      return false unless data.is_a?(Hash)

      patches = PATCHES[data.dig("properties", "id")] || []
      excursions = EXCURSIONS[data.dig("properties", "id")] || []
      spurs = SPURS[data.dig("properties", "id")] || []
      start_trims = START_TRIMS[data.dig("properties", "id")] || []
      end_trims = END_TRIMS[data.dig("properties", "id")] || []
      turnarounds = TURNAROUNDS[data.dig("properties", "id")] || []
      sibling_turnarounds = SIBLING_TURNAROUNDS[data.dig("properties", "id")] || []
      terminus_rewrites = TERMINUS_REWRITES[data.dig("properties", "id")] || []
      features = Array(data["features"])
      stations = features.select { |feature| feature.dig("properties", "feature_type") == "station" }
      changed = false
      features.each do |feature|
        next unless feature.dig("properties", "feature_type") == "route"
        next unless feature.dig("geometry", "type") == "LineString"

        direction = feature.dig("properties", "direction").to_s
        line = feature.dig("geometry", "coordinates")
        patched = line
        patches.each do |patch|
          patched = apply(patched, patch) if direction == patch[:direction].to_s
        end
        excursions.each do |excursion|
          patched = drop_excursion(patched, excursion[:anchor]) if direction == excursion[:direction].to_s
        end
        spurs.each do |spur|
          patched = drop_spur(patched, spur) if direction == spur[:direction].to_s
        end
        start_trims.each do |trim|
          patched = trim_start(patched, trim[:at]) if direction == trim[:direction].to_s
        end
        end_trims.each do |trim|
          patched = trim_end(patched, trim[:at]) if direction == trim[:direction].to_s
        end
        turnarounds.each do |turnaround|
          patched = append_turnaround(patched, turnaround) if direction == turnaround[:direction].to_s
        end
        sibling_turnarounds.each do |turnaround|
          next unless direction == turnaround[:direction].to_s

          resolved = resolve_sibling_turnaround(turnaround)
          patched = append_turnaround(patched, resolved) if resolved
        end
        terminus_rewrites.each do |rewrite|
          next unless direction == rewrite[:direction].to_s

          patched = rewrite[:side] == :start ? rewrite_start(patched, rewrite) : rewrite_end(patched, rewrite)
        end
        stations.each do |station|
          next unless station.dig("properties", "direction").to_s == direction

          circulation = STOP_CIRCULATIONS[station.dig("properties", "name")]
          patched = circulate(patched, station.dig("geometry", "coordinates"), circulation) if circulation
        end
        LOOP_CIRCULATIONS.each { |circulation| patched = loop_through(patched, circulation) }
        TERMINAL_APPROACHES.each { |terminal| patched = approach_terminal(patched, terminal) }
        TERMINAL_LOOPS.each { |terminal| patched = loop_terminal(patched, terminal) }
        patched = gongguan_turn(patched, router)
        next if patched == line

        feature["geometry"]["coordinates"] = patched
        changed = true
      end
      changed | reclaim_banqiao_bay!(features) | banqiao_platforms!(features, router:) |
        linkou_platforms!(data, features) | drop_spur_stops!(features, spurs) |
        kanding!(data, features) | flower_clock!(data, features) |
        nangang_hengke_hub!(data, features) | move_stops!(data, features) |
        tidy_963!(data, features)
    end

    # 新北板橋公車站: four one-way bays off 縣民大道, north (第一月台, by the
    # station) to south (第四月台). TDX parks every stop of a bay on one point,
    # and the 第一／第三月台 points sit between the lanes, so each bay's stops
    # move onto that lane and the visit is redrawn along it.
    BANQIAO_NAME = "新北板橋公車站"
    BANQIAO_RADIUS = 130.0
    BANQIAO_DETOUR_METERS = 1_200.0
    BANQIAO_LANES = {
      "第一月台" => [
        [ 121.4629776, 25.0126811 ], [ 121.4626677, 25.0128855 ], [ 121.4624834, 25.0130080 ],
        [ 121.4623230, 25.0131141 ], [ 121.4621893, 25.0131971 ], [ 121.4621363, 25.0132442 ],
        [ 121.4621253, 25.0133313 ]
      ],
      "第二月台" => [
        [ 121.4629008, 25.0126036 ], [ 121.4627640, 25.0126935 ], [ 121.4626001, 25.0128012 ],
        [ 121.4624197, 25.0129198 ], [ 121.4622125, 25.0130560 ], [ 121.4621452, 25.0131081 ],
        [ 121.4621043, 25.0131721 ], [ 121.4620977, 25.0132422 ], [ 121.4621253, 25.0133313 ]
      ],
      "第三月台" => [
        [ 121.4628251, 25.0125180 ], [ 121.4626962, 25.0126058 ], [ 121.4625323, 25.0127175 ],
        [ 121.4623526, 25.0128399 ], [ 121.4621732, 25.0129621 ], [ 121.4621054, 25.0130060 ]
      ],
      "第四月台" => [
        [ 121.4627526, 25.0124383 ], [ 121.4626139, 25.0125346 ], [ 121.4624660, 25.0126374 ],
        [ 121.4622738, 25.0127709 ], [ 121.4621242, 25.0128748 ]
      ]
    }.freeze
    BANQIAO_BOARDING = {
      "第一月台" => [ 121.4623230, 25.0131141 ],
      "第二月台" => [ 121.4624197, 25.0129198 ],
      "第三月台" => [ 121.4625323, 25.0127175 ],
      "第四月台" => [ 121.4624660, 25.0126374 ]
    }.freeze
    # join_termini sometimes seals both tips on 縣民大道 while the inbound head
    # still drives into 新北板橋公車站. Hand that approach to the outbound so
    # both directions meet at the bay (963 八里－板橋).
    BANQIAO_RECLAIM_JOIN_METERS = 8.0
    BANQIAO_RECLAIM_HEAD_METERS = 700.0
    BANQIAO_RECLAIM_STOP_METERS = 35.0

    # 林口轉運站: 1–7 上客、8–9 僅迄點下車（維基／場站配置）。TDX often
    # parks arrivals on the boarding bay and through routes on 8／9.
    LINKOU_NAME = "林口轉運站"
    LINKOU_BOARDING_PLATFORMS = %w[第1月台 第2月台 第3月台 第4月台 第5月台 第6月台 第7月台].freeze
    LINKOU_ALIGHTING_PLATFORMS = %w[第8月台 第9月台].freeze
    LINKOU_PLATFORMS = {
      "第1月台" => [ 121.361485, 25.067008 ],
      "第2月台" => [ 121.361504, 25.067170 ],
      # 第3／4 sit on the north bay between 第2 and 第5 (no TDX StopPosition).
      "第3月台" => [ 121.361640, 25.067180 ],
      "第4月台" => [ 121.361777, 25.067189 ],
      "第5月台" => [ 121.361913, 25.067199 ],
      "第6月台" => [ 121.361910, 25.067100 ],
      "第7月台" => [ 121.361905, 25.066959 ],
      "第8月台" => [ 121.361792, 25.066877 ],
      "第9月台" => [ 121.361646, 25.066885 ]
    }.freeze
    LINKOU_DEFAULT_ALIGHTING = "第8月台"
    # Wikipedia 候車月台 → TDX direction. Through routes board here; only
    # terminus arrivals use 8／9.
    LINKOU_BOARDING = {
      "new_taipei_760" => { "0" => "第2月台" },
      "new_taipei_786" => { "0" => "第1月台", "1" => "第3月台" }, # 往板橋／往華亞
      "new_taipei_854" => { "0" => "第1月台", "1" => "第4月台" }, # 往寶林／往華亞
      "new_taipei_948" => { "1" => "第2月台" }, # 往林口
      "new_taipei_966sub" => { "0" => "第5月台" },
      "new_taipei_967sub" => { "0" => "第5月台" },
      "new_taipei_937sub" => { "0" => "第6月台" },
      "new_taipei_920sub" => { "0" => "第7月台" }
    }.freeze
    # Departures that TDX parked on an alighting bay (legacy single-platform map).
    LINKOU_DEPARTURE_BOARDING = LINKOU_BOARDING.transform_values { |by_dir| by_dir["0"] }.compact.freeze

    def banqiao_router
      return nil unless Geojson::OsmRoadTiles.available?

      @banqiao_router ||= Geojson::OsmRoadRouter.new
    end

    def reclaim_banqiao_bay!(features)
      outbound = features.find { |feature|
        feature.dig("properties", "feature_type") == "route" &&
          feature.dig("properties", "direction").to_s == "0" &&
          feature.dig("geometry", "type") == "LineString"
      }
      inbound = features.find { |feature|
        feature.dig("properties", "feature_type") == "route" &&
          feature.dig("properties", "direction").to_s == "1" &&
          feature.dig("geometry", "type") == "LineString"
      }
      return false unless outbound && inbound

      out_line = outbound.dig("geometry", "coordinates")
      in_line = inbound.dig("geometry", "coordinates")
      return false if out_line.blank? || in_line.blank? || out_line.length < 2 || in_line.length < 3
      return false if meters_between(out_line.last, in_line.first) > BANQIAO_RECLAIM_JOIN_METERS

      bay_stop = features.find { |feature|
        feature.dig("properties", "feature_type") == "station" &&
          feature.dig("properties", "direction").to_s == "1" &&
          feature.dig("properties", "name") == BANQIAO_NAME
      }
      return false unless bay_stop

      platform = bay_stop.dig("properties", "platform").presence
      boarding = BANQIAO_BOARDING[platform] || bay_stop.dig("geometry", "coordinates")
      return false if boarding.blank?
      return false if meters_between(out_line.last, boarding) <= BANQIAO_RADIUS
      return false if out_line.any? { |point| meters_between(point, boarding) <= BANQIAO_RECLAIM_STOP_METERS }

      cut = nil
      traveled = 0.0
      in_line.each_index do |index|
        break if index.positive? && traveled > BANQIAO_RECLAIM_HEAD_METERS

        traveled += meters_between(in_line[index - 1], in_line[index]) if index.positive?
        next if meters_between(in_line[index], boarding) > BANQIAO_RECLAIM_STOP_METERS

        cut = index
        break
      end
      return false if cut.nil? || cut < 2

      approach = in_line[1..cut].map(&:dup)
      approach[-1] = boarding.dup
      outbound["geometry"]["coordinates"] = out_line + approach
      inbound["geometry"]["coordinates"] = [ boarding.dup ] + in_line[(cut + 1)..].map(&:dup)

      ensure_banqiao_outbound_stop!(features, bay_stop, boarding, platform)
      true
    end

    def ensure_banqiao_outbound_stop!(features, inbound_stop, boarding, platform)
      existing = features.find { |feature|
        feature.dig("properties", "feature_type") == "station" &&
          feature.dig("properties", "direction").to_s == "0" &&
          feature.dig("properties", "name") == BANQIAO_NAME
      }
      if existing
        existing["geometry"]["coordinates"] = boarding.dup
        existing["properties"]["platform"] = platform if platform.present?
        return
      end

      properties = inbound_stop["properties"].dup
      properties["direction"] = 0
      properties["platform"] = platform if platform.present?
      features << {
        "type" => "Feature",
        "properties" => properties,
        "geometry" => { "type" => "Point", "coordinates" => boarding.dup }
      }
    end

    # 963: joint 指南／淡水; terminus 新北板橋公車站. Express spur is dropped via SPURS.
    def tidy_963!(data, features)
      return false unless data.dig("properties", "id") == "new_taipei_963"

      properties = data["properties"]
      changed = false
      if properties["destination"] != BANQIAO_NAME
        properties["destination"] = BANQIAO_NAME
        changed = true
      end
      if properties["operator_2"].blank?
        properties["operator_2"] = "淡水客運"
        properties["operator_2_en"] = "Tamshui Bus"
        changed = true
      end
      changed
    end

    def banqiao_platforms!(features, router: nil)
      stations = features.select { |feature| feature.dig("properties", "name") == BANQIAO_NAME }
      return false if stations.empty?

      router ||= banqiao_router
      return false unless router

      # 702／藍38: TDX only publishes 新北板橋公車站 on the departure, while the
      # arrival tip dies on 縣民大道 ~40 m short of the bay. Reuse the sibling
      # platform so both tips meet at the same boarding point.
      platform_by_direction = stations.each_with_object({}) do |stop, map|
        platform = stop.dig("properties", "platform").presence
        map[stop.dig("properties", "direction").to_s] = platform if platform
      end
      shared_platform = platform_by_direction.values.first

      changed = false
      features.each do |feature|
        next unless feature.dig("properties", "feature_type") == "route"
        next unless feature.dig("geometry", "type") == "LineString"

        direction = feature.dig("properties", "direction").to_s
        station = stations.find { |stop| stop.dig("properties", "direction").to_s == direction }
        platform = platform_by_direction[direction]
        platform ||= shared_platform if shared_platform && banqiao_tip_near?(feature.dig("geometry", "coordinates"), shared_platform)
        lane = BANQIAO_LANES[platform]
        boarding = BANQIAO_BOARDING[platform]
        next unless lane && boarding

        line = feature.dig("geometry", "coordinates")
        patched = drive_banqiao(line, lane, boarding, router)
        if patched != line
          feature["geometry"]["coordinates"] = patched
          changed = true
        end
        next unless station
        next unless patched != line || lane_covered?(patched, lane)
        next if station.dig("geometry", "coordinates") == boarding

        station["geometry"]["coordinates"] = boarding.dup
        changed = true
      end
      changed
    end

    def banqiao_tip_near?(line, platform)
      boarding = BANQIAO_BOARDING[platform]
      return false if line.blank? || boarding.nil?

      meters_between(line.first, boarding) <= BANQIAO_RADIUS ||
        meters_between(line.last, boarding) <= BANQIAO_RADIUS
    end

    # The bay is one-way off 縣民大道. A visit inside BANQIAO_RADIUS of the
    # boarding point is replaced by the drive along the bay: arrival ends
    # there, departure starts there, and a through route runs the whole bay.
    def drive_banqiao(line, lane, boarding, router)
      return line if lane_covered?(line, lane)

      nearest = line.each_index.min_by { |index| meters_between(line[index], boarding) }
      return line if meters_between(line[nearest], boarding) > BANQIAO_RADIUS

      first = nearest
      first -= 1 while first.positive? && meters_between(line[first - 1], boarding) <= BANQIAO_RADIUS
      last = nearest
      last += 1 while last + 1 < line.length && meters_between(line[last + 1], boarding) <= BANQIAO_RADIUS
      return line if first.zero? && last == line.length - 1

      if first.zero?
        tail = router.route(lane.last, line[last + 1])
        return line unless tail && Geojson::BusShapeTrimmer.path_length(tail) <= BANQIAO_DETOUR_METERS

        return join_paths(lane_from(lane, boarding), tail, line[(last + 1)..])
      end

      if last == line.length - 1
        head = router.route(line[first - 1], lane.first)
        return line unless head && Geojson::BusShapeTrimmer.path_length(head) <= BANQIAO_DETOUR_METERS

        return join_paths(line[0...first], head, lane_until(lane, boarding))
      end

      into = router.route(line[first - 1], lane.first)
      out = router.route(lane.last, line[last + 1])
      return line unless into && out
      return line if Geojson::BusShapeTrimmer.path_length(into) > BANQIAO_DETOUR_METERS ||
        Geojson::BusShapeTrimmer.path_length(out) > BANQIAO_DETOUR_METERS

      join_paths(line[0...first], into, lane, out, line[(last + 1)..])
    end

    def lane_covered?(line, lane)
      lane.count { |point| distance_to_line(line, point) <= 3 } >= (lane.length * 0.8)
    end

    def lane_from(lane, boarding)
      index = lane.index { |point| meters_between(point, boarding) < 1 } || 0
      lane[index..].map(&:dup)
    end

    def lane_until(lane, boarding)
      index = lane.index { |point| meters_between(point, boarding) < 1 } || (lane.length - 1)
      lane[0..index].map(&:dup)
    end

    # Split 林口轉運站 boarding (1–7) from alighting (8–9). Terminus arrivals
    # move to 第8月台; departures／through stops follow Wikipedia 候車月台.
    def linkou_platforms!(data, features)
      stations = features.select { |feature| feature.dig("properties", "name") == LINKOU_NAME }
      return false if stations.empty?

      route_id = data.dig("properties", "id").to_s
      by_direction = features
        .select { |feature| feature.dig("properties", "feature_type") == "station" }
        .group_by { |feature| feature.dig("properties", "direction").to_s }

      changed = false
      by_direction.each do |direction, stops|
        next if stops.empty?

        first = stops.first
        last = stops.last
        terminus_arrival = last.dig("properties", "name") == LINKOU_NAME && last.object_id != first.object_id

        if terminus_arrival
          platform = last.dig("properties", "platform").to_s
          if LINKOU_BOARDING_PLATFORMS.include?(platform) || platform.blank?
            changed |= assign_linkou_platform!(last, LINKOU_DEFAULT_ALIGHTING)
            changed |= snap_linkou_line_tip!(features, direction, :end, LINKOU_PLATFORMS.fetch(LINKOU_DEFAULT_ALIGHTING))
          elsif LINKOU_ALIGHTING_PLATFORMS.include?(platform)
            changed |= assign_linkou_platform!(last, platform)
            changed |= snap_linkou_line_tip!(features, direction, :end, LINKOU_PLATFORMS.fetch(platform))
          end
        end

        boarding = LINKOU_BOARDING.dig(route_id, direction)
        boarding ||= LINKOU_DEPARTURE_BOARDING[route_id] if first.dig("properties", "name") == LINKOU_NAME

        stops.each do |stop|
          next unless stop.dig("properties", "name") == LINKOU_NAME
          next if terminus_arrival && stop.object_id == last.object_id

          platform = boarding
          platform ||= stop.dig("properties", "platform") if LINKOU_BOARDING_PLATFORMS.include?(stop.dig("properties", "platform").to_s)
          if platform.nil? && stop.object_id == first.object_id && LINKOU_ALIGHTING_PLATFORMS.include?(stop.dig("properties", "platform").to_s)
            platform = stops.find { |sibling|
              LINKOU_BOARDING_PLATFORMS.include?(sibling.dig("properties", "platform").to_s)
            }&.dig("properties", "platform")
          end
          next unless platform && LINKOU_PLATFORMS[platform]
          next if LINKOU_ALIGHTING_PLATFORMS.include?(platform)

          from = stop.dig("geometry", "coordinates")
          changed |= assign_linkou_platform!(stop, platform)
          point = LINKOU_PLATFORMS.fetch(platform)
          if stop.object_id == first.object_id
            changed |= snap_linkou_line_tip!(features, direction, :start, point)
          else
            changed |= snap_linkou_near!(features, direction, from, point)
          end
        end
      end
      changed
    end

    def assign_linkou_platform!(station, platform)
      point = LINKOU_PLATFORMS.fetch(platform)
      properties = station["properties"]
      already = properties["platform"] == platform && station.dig("geometry", "coordinates") == point
      return false if already

      properties["platform"] = platform
      station["geometry"]["coordinates"] = point.dup
      true
    end

    def snap_linkou_line_tip!(features, direction, side, point)
      line = linkou_route_line(features, direction)
      return false unless line

      coordinates = line.dig("geometry", "coordinates")
      return false if coordinates.blank?

      tip = side == :start ? coordinates.first : coordinates.last
      return false if tip == point
      return false if meters_between(tip, point) > 80

      if side == :start
        coordinates[0] = point.dup
      else
        coordinates[-1] = point.dup
      end
      true
    end

    def snap_linkou_near!(features, direction, from, point)
      line = linkou_route_line(features, direction)
      return false unless line

      coordinates = line.dig("geometry", "coordinates")
      return false if coordinates.blank? || from.blank?

      nearest = coordinates.each_index.min_by { |index| meters_between(coordinates[index], from) }
      return false if meters_between(coordinates[nearest], from) > 80
      return false if coordinates[nearest] == point

      coordinates[nearest] = point.dup
      true
    end

    def linkou_route_line(features, direction)
      features.find do |feature|
        feature.dig("properties", "feature_type") == "route" &&
          feature.dig("properties", "direction").to_s == direction.to_s &&
          feature.dig("geometry", "type") == "LineString"
      end
    end

    def join_paths(*parts)
      parts.flatten(1).chunk_while { |left, right| meters_between(left, right) < 1 }.map { |chunk| chunk.first.dup }
    end

    def circulate(line, stop, circulation)
      min_lon, min_lat, max_lon, max_lat = circulation[:bounds]
      inside = ->(point) { point[0].between?(min_lon, max_lon) && point[1].between?(min_lat, max_lat) }

      runs = []
      index = 0
      while index < line.length
        unless inside.call(line[index])
          index += 1
          next
        end

        last = index
        last += 1 while last + 1 < line.length && inside.call(line[last + 1])
        runs << [ index, last ]
        index = last + 1
      end

      patched = line
      runs.reverse_each do |first, last|
        next if first.zero? || last + 1 >= line.length
        next if (first..last).none? { |i| meters_between(line[i], stop) <= circulation[:max_stop_meters] }
        next unless line[last + 1][0] < circulation[:west_of]

        side = line[first - 1][0] < circulation[:west_of] ? :west : :east
        path = circulation[:paths][side]
        next if patched[first..last] == path

        patched = patched[0...first] + path.map(&:dup) + patched[(last + 1)..]
      end
      patched == line ? line : remove_spikes(patched, stop)
    end

    def loop_through(line, circulation)
      loop_line = circulation[:loop]
      margin = circulation[:max_meters] / 100_000.0
      lons, lats = loop_line.transpose
      return line unless line.any? { |lon, lat|
        lon.between?(lons.min - margin, lons.max + margin) && lat.between?(lats.min - margin, lats.max + margin)
      }

      near = line.map { |point| loop_projection(loop_line, point)[:distance] <= circulation[:max_meters] }
      return line unless near.any?

      result = []
      index = 0
      changed = false
      while index < line.length
        unless near[index]
          result << line[index]
          index += 1
          next
        end

        last = index
        last += 1 while last + 1 < line.length && near[last + 1]
        run = line[index..last]
        path = loop_path(circulation, run)
        if path && path != run
          result.concat(path)
          changed = true
        else
          result.concat(run)
        end
        index = last + 1
      end
      changed ? result : line
    end

    # The loop stretch between where `run` joins and leaves it, going whichever
    # way round stays closest to `run`.
    def loop_path(circulation, run)
      loop_line = circulation[:loop]
      entry = snap_to_junction(circulation, loop_projection(loop_line, run.first))
      exit = snap_to_junction(circulation, loop_projection(loop_line, run.last))
      total = Geojson::BusShapeTrimmer.path_length(loop_line)
      forward = loop_walk(loop_line, entry, exit, total, :forward)
      backward = loop_walk(loop_line, entry, exit, total, :backward)
      return nil if Geojson::BusShapeTrimmer.path_length(forward) < 1.0 && Geojson::BusShapeTrimmer.path_length(run) < 1.0

      candidates = [ forward, backward ]
      candidates << loop_walk(loop_line, entry, exit, total, :forward, extra_lap: true) if (exit[:at] - entry[:at]) % total < LOOP_SNAP_METERS * 2
      candidates.min_by { |path| (fit_error(path, run) * 10).round }
    end

    def loop_walk(loop_line, from, to, total, way, extra_lap: false)
      offsets = []
      position = 0.0
      loop_line.each_cons(2) do |a, b|
        offsets << [ position, a ]
        position += meters_between(a, b)
      end
      span = way == :forward ? (to[:at] - from[:at]) % total : (from[:at] - to[:at]) % total
      span += total if extra_lap
      laps = extra_lap ? [ 0.0, total ] : [ 0.0 ]
      between = offsets.flat_map do |at, point|
        offset = way == :forward ? (at - from[:at]) % total : (from[:at] - at) % total
        laps.filter_map { |lap| [ offset + lap, point.dup ] if (offset + lap).positive? && offset + lap < span }
      end
      [ from[:point] ] + between.sort_by(&:first).map(&:last) + [ to[:point] ]
    end

    def loop_projection(loop_line, point)
      best = nil
      position = 0.0
      loop_line.each_cons(2) do |a, b|
        projection = Geojson::BusShapeTrimmer.project(point, a, b)
        if best.nil? || projection[:distance] < best[:distance]
          best = { distance: projection[:distance], point: projection[:point], at: position + meters_between(a, projection[:point]) }
        end
        position += meters_between(a, b)
      end
      best
    end

    # Joins and leaves happen at the loop's junctions; snapping there avoids a
    # short back-and-forth jog where the projection lands just past the corner.
    def snap_to_junction(circulation, projection)
      junction = circulation[:junctions]
        .map { |point| [ point, meters_between(point, projection[:point]) ] }
        .select { |_, gap| gap <= LOOP_SNAP_METERS }
        .min_by(&:last)&.first
      return projection unless junction

      loop_projection(circulation[:loop], junction).merge(point: junction.dup)
    end

    # Mean distance from the original stretch to a candidate path, both ways
    # round, so a path that skips part of the stretch scores badly too.
    def fit_error(path, run)
      to_path = run.sum { |point| distance_to_line(path, point) } / run.length
      to_run = path.sum { |point| distance_to_line(run, point) } / path.length
      to_path + to_run
    end

    def distance_to_line(line, point)
      return meters_between(line.first, point) if line.length < 2

      line.each_cons(2).map { |a, b| Geojson::BusShapeTrimmer.project(point, a, b)[:distance] }.min
    end

    # Drop A → B → A out-and-back jogs (shape noise at the hub entrances).
    def remove_spikes(line, center)
      result = line.dup
      index = 1
      while index < result.length - 1
        if meters_between(result[index], center) <= SPIKE_RADIUS_METERS &&
            meters_between(result[index - 1], result[index + 1]) < 2.0 &&
            meters_between(result[index - 1], result[index]) > 5.0
          result.slice!(index, 2)
          index = [ index - 1, 1 ].max
        else
          index += 1
        end
      end
      result
    end

    def gongguan_turn(line, router)
      runs = gongguan_ring_runs(line)
      return line if runs.empty?

      road_router = router || OsmRoadRouter.new
      runs.reverse_each do |start_index, finish_index|
        line = replace_gongguan_sweep(line, start_index, finish_index, road_router)
      end
      line
    end

    def gongguan_ring_runs(line)
      indexes = line.each_index.select { |index| meters_between(line[index], GONGGUAN_CENTER) <= GONGGUAN_NEAR_METERS }
      return [] if indexes.length < 3

      runs = []
      run = [ indexes.first ]
      indexes.each_cons(2) { |left, right| right == left + 1 ? run << right : (runs << run; run = [ right ]) }
      runs << run
      runs.filter_map do |indexes_in_run|
        next if indexes_in_run.length < 3

        start_index = indexes_in_run.first
        finish_index = indexes_in_run.last
        sweep = line[start_index..finish_index]
        extra = Geojson::BusShapeTrimmer.path_length(sweep) - meters_between(sweep.first, sweep.last)
        [ start_index, finish_index ] if extra >= GONGGUAN_EXTRA_METERS
      end
    end

    # Endpoints that still sit on the old ring snap onto a one-way the wrong way
    # and the router detours for kilometres. Try the neighbouring vertices, which
    # are out on the approach roads, and keep the shortest path that is not a detour.
    def replace_gongguan_sweep(line, start_index, finish_index, router)
      best = nil
      gongguan_anchors(line, start_index, -1).each do |start_at|
        gongguan_anchors(line, finish_index, 1).each do |finish_at|
          next if finish_at <= start_at + 1

          road = router.route(line[start_at], line[finish_at])
          next unless road.is_a?(Array) && road.length >= 2

          span = line[start_at..finish_at]
          road_length = Geojson::BusShapeTrimmer.path_length(road)
          next if road_length > Geojson::BusShapeTrimmer.path_length(span) + GONGGUAN_DETOUR_METERS
          next if span[1...-1].none? { |point| distance_to_line(road, point) > GONGGUAN_OFF_METERS }
          next if best && road_length >= best[:length]

          best = { start_at: start_at, finish_at: finish_at, road: road, length: road_length }
        end
      end
      return line unless best

      line[0...best[:start_at]] + best[:road] + line[(best[:finish_at] + 1)..]
    end

    def gongguan_anchors(line, index, step)
      anchors = [ index ]
      cursor = index
      6.times do
        nxt = cursor + step
        break if nxt.negative? || nxt >= line.length
        break if meters_between(line[nxt], GONGGUAN_CENTER) > GONGGUAN_ANCHOR_METERS

        anchors << nxt
        cursor = nxt
      end
      anchors
    end

    def drop_spur(line, spur)
      tip_index = line.each_index.min_by { |index| meters_between(line[index], spur[:tip]) }
      return line if tip_index.nil? || meters_between(line[tip_index], spur[:tip]) > SPUR_TIP_METERS

      leave = (0...tip_index).reverse_each.find { |index| meters_between(line[index], spur[:leave]) <= SPUR_LEAVE_METERS }
      back = ((tip_index + 1)...line.length).find { |index| meters_between(line[index], spur[:leave]) <= SPUR_LEAVE_METERS }
      return line unless leave && back
      return line if Geojson::BusShapeTrimmer.path_length(line[leave..back]) < MIN_SPUR_METERS

      line[0..leave] + line[back..]
    end

    def trim_start(line, at)
      return line if line.length < 3
      return line if meters_between(line.first, at) <= START_TRIM_METERS

      index = line.each_index.find { |i| meters_between(line[i], at) <= START_TRIM_METERS }
      return line[index..] if index&.positive?

      best = nearest_projection(line, at)
      return line unless best && best[:distance] <= END_TRIM_METERS

      ([ best[:point] ] + line[(best[:segment] + 1)..]).chunk_while { |a, b| a == b }.map(&:first)
    end

    def trim_end(line, at)
      return line if line.length < 3
      return line if meters_between(line.last, at) <= START_TRIM_METERS

      index = line.each_index.select { |i| meters_between(line[i], at) <= START_TRIM_METERS }.max
      return line[0..index] if index && index < line.length - 1

      best = nearest_projection(line, at)
      return line unless best && best[:distance] <= END_TRIM_METERS

      (line[0..best[:segment]] + [ best[:point] ]).chunk_while { |a, b| a == b }.map(&:first)
    end

    def nearest_projection(line, at)
      best = nil
      line.each_cons(2).with_index do |(a, b), segment|
        projection = Geojson::BusShapeTrimmer.project(at, a, b)
        next if best && projection[:distance] >= best[:distance]

        best = projection.merge(segment:)
      end
      best
    end

    def drop_spur_stops!(features, spurs)
      return false if spurs.empty?

      lines = features.select { |feature| feature.dig("properties", "feature_type") == "route" }
        .to_h { |feature| [ feature.dig("properties", "direction").to_s, feature.dig("geometry", "coordinates") ] }
      removed = false
      features.reject! do |feature|
        next false unless feature.dig("properties", "feature_type") == "station"

        direction = feature.dig("properties", "direction").to_s
        spur = spurs.find { |entry| entry[:direction].to_s == direction && entry[:stop] == feature.dig("properties", "name") }
        line = lines[direction]
        next false unless spur && line && distance_to_line(line, feature.dig("geometry", "coordinates")) > SPUR_STOP_METERS

        removed = true
      end
      removed
    end

    def kanding!(data, features)
      case data.dig("properties", "id")
      when KANDING_MAIN_ID then add_kanding_stops!(data, features)
      when KANDING_SKIP_ID then straighten_kanding_skip!(features) | drop_kanding_stops!(features)
      else false
      end
    end

    # 823 around 南港展覽館: TDX climbs onto 經貿二路 (~25.059) between the
    # 經貿一路 and 南港路 stops, and the three 橫科 poles (outbound + two
    # inbound passages) stack on top of each other. Flatten the exhibition
    # block to 經貿一路 → west connector → 南港路, and park each 橫科 on its
    # own passage with a direction note.
    NANGANG_HENGKE_ROUTE_ID = "new_taipei_823"
    NANGANG_EXPO_OUT_FROM = [ 121.619716, 25.056329 ].freeze # 經貿一路
    NANGANG_EXPO_OUT_TO = [ 121.617965, 25.054879 ].freeze   # 南港路 (去程)
    NANGANG_EXPO_IN_FROM = [ 121.617342, 25.055143 ].freeze  # 南港路 (返程)
    NANGANG_EXPO_IN_TO = [ 121.62145, 25.05481 ].freeze      # 橫科 second pass
    NANGANG_EXPO_OUT_LOOP = [
      [ 121.619200, 25.056400 ], [ 121.618400, 25.056480 ], [ 121.617600, 25.056450 ],
      [ 121.616950, 25.056300 ], [ 121.616720, 25.055900 ], [ 121.616650, 25.055400 ],
      [ 121.616700, 25.055120 ], [ 121.617050, 25.055020 ], [ 121.617500, 25.054960 ]
    ].freeze
    NANGANG_EXPO_IN_LOOP = [
      [ 121.616900, 25.055050 ], [ 121.616650, 25.055350 ], [ 121.616700, 25.055850 ],
      [ 121.616950, 25.056300 ], [ 121.617700, 25.056480 ], [ 121.618600, 25.056450 ],
      [ 121.619500, 25.056350 ], [ 121.620300, 25.056150 ], [ 121.620700, 25.055600 ],
      [ 121.620900, 25.055050 ], [ 121.621200, 25.054900 ]
    ].freeze
    # direction / sequence among same-name stops → pole + list note.
    # Keep each pole on its true passage so nearest-line projection stays
    # monotonic with eBus order (去程 橫科 after the exhibition loop; 返程
    # first 橫科 on the approach, second on the southbound exit to 舊莊).
    NANGANG_HENGKE_STOPS = [
      { direction: "0", index: 0, coordinates: [ 121.62220, 25.05470 ], note: "往汐止" },
      { direction: "1", index: 0, coordinates: [ 121.62250, 25.05512 ], note: "往南港展覽館" },
      { direction: "1", index: 1, coordinates: [ 121.62140, 25.05450 ], note: "往舊莊" }
    ].freeze

    def nangang_hengke_hub!(data, features)
      return false unless data.dig("properties", "id") == NANGANG_HENGKE_ROUTE_ID

      changed = false
      features.each do |feature|
        next unless feature.dig("properties", "feature_type") == "route"
        next unless feature.dig("geometry", "type") == "LineString"

        direction = feature.dig("properties", "direction").to_s
        line = feature.dig("geometry", "coordinates")
        patched =
          if direction == "0"
            replace_span(line, NANGANG_EXPO_OUT_FROM, NANGANG_EXPO_OUT_TO, NANGANG_EXPO_OUT_LOOP)
          elsif direction == "1"
            replace_span(line, NANGANG_EXPO_IN_FROM, NANGANG_EXPO_IN_TO, NANGANG_EXPO_IN_LOOP)
          end
        next unless patched && patched != line

        feature["geometry"]["coordinates"] = patched
        changed = true
      end

      changed | place_nangang_hengke_stops!(features)
    end

    def replace_span(line, from_pt, to_pt, middle)
      from = nearest_index(line, from_pt)
      to = nearest_index(line, to_pt)
      return nil unless from && to && to > from + 1

      # Only rewrite the exhibition block when it still climbs north of 經貿一路.
      return nil unless line[from..to].any? { |point| point[1] > 25.0572 }

      line[0..from] + middle.map(&:dup) + line[to..]
    end

    def place_nangang_hengke_stops!(features)
      by_direction = features
        .select { |feature| feature.dig("properties", "feature_type") == "station" && feature.dig("properties", "name") == "橫科" }
        .group_by { |feature| feature.dig("properties", "direction").to_s }

      changed = false
      NANGANG_HENGKE_STOPS.each do |spec|
        stop = Array(by_direction[spec[:direction]])[spec[:index]]
        next unless stop

        if stop.dig("geometry", "coordinates") != spec[:coordinates]
          stop["geometry"]["coordinates"] = spec[:coordinates].dup
          changed = true
        end
        if stop.dig("properties", "note") != spec[:note]
          stop["properties"]["note"] = spec[:note]
          changed = true
        end
      end
      changed
    end

    def nearest_index(line, point)
      return nil if line.blank?

      line.each_index.min_by { |index| meters_between(line[index], point) }
    end

    def add_kanding_stops!(data, features)
      line = direction_line(features, "1")
      return false unless line
      return false unless KANDING_STOPS.all? { |stop| distance_to_line(line, stop[:coordinates]) <= KANDING_STOP_METERS }

      present = features.select { |feature| station?(feature, "1") }.map { |feature| feature.dig("properties", "name") }
      missing = KANDING_STOPS.reject { |stop| present.include?(stop[:name]) }
      return false if missing.empty?

      anchor = features.rindex { |feature| station?(feature, "1") && feature.dig("properties", "name") == "崁頂(中華路)" }
      missing.reverse_each do |stop|
        features.insert(anchor ? anchor + 1 : features.length, kanding_stop(data, stop))
      end
      true
    end

    def straighten_kanding_skip!(features)
      changed = false
      features.each do |feature|
        next unless feature.dig("properties", "feature_type") == "route"
        next unless feature.dig("properties", "direction").to_s == "1"

        line = feature.dig("geometry", "coordinates")
        patched = replace_kanding_loop(line)
        next if patched == line

        feature["geometry"]["coordinates"] = patched
        changed = true
      end
      changed
    end

    def replace_kanding_loop(line)
      return line if distance_to_line(line, KANDING_TIP) > KANDING_TIP_METERS

      tip_index = line.each_index.min_by { |index| meters_between(line[index], KANDING_TIP) }
      return line if tip_index.nil?

      leave = (0...tip_index).reverse_each.find { |index| meters_between(line[index], KANDING_LEAVE) <= KANDING_JOIN_METERS }
      back = ((tip_index + 1)...line.length).find { |index| meters_between(line[index], KANDING_BACK) <= KANDING_JOIN_METERS }
      return line unless leave && back

      line[0..leave] + KANDING_DIRECT.map(&:dup) + line[back..]
    end

    def drop_kanding_stops!(features)
      removed = false
      names = KANDING_STOPS.map { |stop| stop[:name] }
      features.reject! do |feature|
        next false unless station?(feature, "1") && names.include?(feature.dig("properties", "name"))

        removed = true
      end
      removed
    end

    def kanding_stop(data, stop)
      {
        "type" => "Feature",
        "properties" => {
          "feature_type" => "station",
          "ref" => stop[:ref],
          "name" => stop[:name],
          "name_en" => stop[:name_en],
          "line" => data.dig("properties", "name"),
          "color" => data.dig("properties", "color"),
          "direction" => 1,
          "station_id" => stop[:station_id]
        },
        "geometry" => { "type" => "Point", "coordinates" => stop[:coordinates].dup }
      }
    end

    def flower_clock!(data, features)
      return false unless data.dig("properties", "id") == FLOWER_ROUTE_ID

      changed = false
      FLOWER_DIRECTIONS.each do |direction, spec|
        line = direction_line(features, direction)
        next if line.nil? || distance_to_line(line, FLOWER_POINT) > FLOWER_METERS
        next if features.any? { |feature| station?(feature, direction) && feature.dig("properties", "name") == "第一停車場(花鐘)" }

        index = features.index { |feature| station?(feature, direction) && feature.dig("properties", "name") == spec[:anchor] }
        next unless index

        if spec[:place] == :before
          spec[:stops].each_with_index { |stop, offset| features.insert(index + offset, flower_stop(data, stop, direction.to_i)) }
        else
          spec[:stops].reverse_each { |stop| features.insert(index + 1, flower_stop(data, stop, direction.to_i)) }
        end
        changed = true
      end
      changed
    end

    def flower_stop(data, stop, direction)
      {
        "type" => "Feature",
        "properties" => {
          "feature_type" => "station",
          "ref" => stop[:ref],
          "name" => stop[:name],
          "name_en" => stop[:name_en],
          "line" => data.dig("properties", "name"),
          "color" => data.dig("properties", "color"),
          "direction" => direction,
          "station_id" => stop[:station_id]
        },
        "geometry" => { "type" => "Point", "coordinates" => stop[:coordinates].dup }
      }
    end

    def direction_line(features, direction)
      features.find { |feature|
        feature.dig("properties", "feature_type") == "route" && feature.dig("properties", "direction").to_s == direction
      }&.dig("geometry", "coordinates")
    end

    def station?(feature, direction)
      feature.dig("properties", "feature_type") == "station" && feature.dig("properties", "direction").to_s == direction
    end

    def drop_excursion(line, anchor)
      near = line.each_index.select { |index| meters_between(line[index], anchor) <= EXCURSION_ANCHOR_METERS }
      first = near.first
      last = near.last
      return line if first.nil? || last == first || last + 1 >= line.length
      return line if Geojson::BusShapeTrimmer.path_length(line[first..last]) < MIN_EXCURSION_METERS

      line[0..first] + line[(last + 1)..]
    end

    def append_turnaround(line, turnaround)
      return line if line.length < 2
      return line if meters_between(line.last, turnaround[:from]) > TURNAROUND_FROM_METERS

      path = turnaround[:path]
      if turnaround[:reuse_outbound]
        # Retraces the outbound approach; tip at path.last means already applied.
        return line if meters_between(line.last, path.last) <= TURNAROUND_FROM_METERS
      else
        # Idempotency: path may return near `from` (e.g. 紅5 U-turn), so endpoint
        # proximity to path.last is ambiguous — require a mid-path checkpoint.
        checkpoint = path.max_by { |point| meters_between(turnaround[:from], point) }
        if checkpoint && line.any? { |point| meters_between(point, checkpoint) <= TURNAROUND_FROM_METERS }
          return line
        end
      end

      start = meters_between(line.last, path.first) <= VERTEX_MATCH_METERS ? 1 : 0
      line + path[start..].map(&:dup)
    end

    def resolve_sibling_turnaround(turnaround)
      path = sibling_turnaround_path(turnaround)
      return nil if path.blank?

      turnaround.merge(path: path)
    end

    def sibling_turnaround_path(turnaround)
      path = Geojson::BusLayout.find_geojson(turnaround[:sibling_id])
      return nil unless path&.exist?

      data = JSON.parse(File.read(path))
      line = direction_line(Array(data["features"]), turnaround[:sibling_direction].to_s)
      return nil if line.blank?

      from_index = line.each_index.min_by { |index| meters_between(line[index], turnaround[:from]) }
      to_index = line.each_index.min_by { |index| meters_between(line[index], turnaround[:until]) }
      return nil if from_index.nil? || to_index.nil? || to_index <= from_index
      return nil if meters_between(line[from_index], turnaround[:from]) > SIBLING_TURNAROUND_SNAP_METERS
      return nil if meters_between(line[to_index], turnaround[:until]) > SIBLING_TURNAROUND_SNAP_METERS

      line[from_index..to_index].map(&:dup)
    rescue JSON::ParserError
      nil
    end

    def rewrite_end(line, rewrite)
      index = nearest_vertex_index(line, rewrite[:at])
      return line unless index
      return line if meters_between(line.last, rewrite[:path].last) <= TERMINUS_AT_METERS

      line[0..index] + rewrite[:path].map(&:dup)
    end

    def rewrite_start(line, rewrite)
      index = nearest_vertex_index(line, rewrite[:at])
      return line unless index
      return line if meters_between(line.first, rewrite[:path].first) <= TERMINUS_AT_METERS

      path = rewrite[:path].map(&:dup)
      path = path[0...-1] if meters_between(path.last, line[index]) <= VERTEX_MATCH_METERS
      path + line[index..]
    end

    def nearest_vertex_index(line, target)
      index = line.each_index.min_by { |i| meters_between(line[i], target) }
      return nil if index.nil? || meters_between(line[index], target) > TERMINUS_AT_METERS

      index
    end

    def approach_terminal(line, terminal)
      return line if line.length < 2
      return line if meters_between(line[-1], terminal[:departure]) > terminal[:departure_meters]
      return line if meters_between(line[-2], terminal[:arrival]) > terminal[:arrival_meters]

      line[0..-2] + terminal[:path].map(&:dup) + [ line[-1] ]
    end

    def loop_terminal(line, terminal)
      return line if line.length < 2

      near_entry = ->(index) { meters_between(line[index], terminal[:arrival].first) <= terminal[:join_meters] }
      near_exit = ->(index) { meters_between(line[index], terminal[:departure].last) <= terminal[:join_meters] }

      if meters_between(line.last, terminal[:stop]) <= terminal[:stop_meters]
        last = (line.length - 1).downto(0).find { |index| near_entry.call(index) }
        if last
          first = last
          first -= 1 while first.positive? && near_entry.call(first - 1)
          line = line[0...first] + terminal[:arrival].map(&:dup)
        end
      end

      if meters_between(line.first, terminal[:stop]) <= terminal[:stop_meters]
        first = (0...line.length).find { |index| near_exit.call(index) }
        if first
          last = first
          last += 1 while last + 1 < line.length && near_exit.call(last + 1)
          line = terminal[:departure].map(&:dup) + line[(last + 1)..]
        end
      end

      line
    end

    def apply(line, patch)
      from = line.index { |point| meters_between(point, patch[:from]) <= VERTEX_MATCH_METERS }
      return line unless from

      to = (from + 1...line.length).find { |index| meters_between(line[index], patch[:to]) <= VERTEX_MATCH_METERS }
      return line unless to

      left = patch[:exclusive_from] ? line[0...from] : line[0..from]
      right = patch[:exclusive_to] ? line[(to + 1)..] : line[to..]
      left + patch[:path].map(&:dup) + right
    end

    def move_stops!(data, features)
      moves = STOP_MOVES[data.dig("properties", "id")] || []
      return false if moves.empty?

      moved = false
      features.each do |feature|
        next unless feature.dig("properties", "feature_type") == "station"

        move = moves.find { |entry|
          entry[:direction].to_s == feature.dig("properties", "direction").to_s &&
            entry[:name] == feature.dig("properties", "name")
        }
        next unless move
        next if feature.dig("geometry", "coordinates") == move[:coordinates]

        feature["geometry"]["coordinates"] = move[:coordinates].dup
        moved = true
      end
      moved
    end

    def meters_between(left, right)
      Geojson::BusLoopCloser.meters_between(left, right)
    end
  end
end
