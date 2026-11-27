# AMuse 家具自動生成スクリプト（SketchUp Ruby）
# 画像と寸法図から起こした、黄色い子供用ハイチェアの近似モデルです
#
# 使い方:
#   SketchUp の Ruby コンソールで下記を実行
#     load '（このファイルのフルパス）'
#   読み込むと「AMuse_黄色い椅子」というグループが作られます
#   再読み込みすると、前回の自動生成分だけ消えて作り直されます
#
# 寸法の根拠（寸法図より）:
#   全高 790mm / 座面高さ 520mm / 座面 幅280mm × 奥行290mm
#   脚の広がり（接地面）幅410mm × 奥行430mm
# 写真からの近似:
#   脚・背もたれのスピンドル・足掛けバーの太さ、座面の厚み、色（マスタードイエロー）
#   座面の角の丸みや脚先の細りは簡略化しています

module AMuseChair
  CONFIG = {
    total_height_mm: 790,   # 全高
    seat_height_mm:  520,   # 座面の上面までの高さ
    seat_w_mm:       280,   # 座面の幅
    seat_d_mm:       290,   # 座面の奥行
    seat_t_mm:        30,   # 座面の厚み
    foot_w_mm:       410,   # 接地面での脚の広がり（幅）
    foot_d_mm:       430,   # 接地面での脚の広がり（奥行）
    leg_top_r_mm:     17,   # 脚の半径（上）
    leg_bottom_r_mm:  13,   # 脚の半径（下）
    rung_r_mm:        11,   # 足掛けバーの半径
    rung_z_mm:       175,   # 足掛けバーの高さ
    spindle_r_mm:     11,   # 背もたれスピンドルの半径
    rail_h_mm:        70,   # 背もたれ上部の板の高さ
    rail_t_mm:        24    # 背もたれ上部の板の厚み
  }.freeze

  GROUP_NAME = 'AMuse_黄色い椅子'.freeze
  SEGMENTS = 28 # 丸棒の分割数（v2で14→28に増やして滑らかに）

  def self.yellow_material(model)
    mat = model.materials['椅子_マスタードイエロー'] || model.materials.add('椅子_マスタードイエロー')
    mat.color = Sketchup::Color.new(216, 178, 64)
    mat
  end

  def self.paint(group, mat)
    group.entities.grep(Sketchup::Face).each do |f|
      f.material = mat
      f.back_material = mat
    end
  end

  # 箱を作る（x,y,z は最小コーナー、w,d,h は寸法。すべて mm）
  def self.add_box(parent, x, y, z, w, d, h, mat, name)
    group = parent.add_group
    group.name = name
    ents = group.entities
    pts = [
      Geom::Point3d.new(x.mm, y.mm, z.mm),
      Geom::Point3d.new((x + w).mm, y.mm, z.mm),
      Geom::Point3d.new((x + w).mm, (y + d).mm, z.mm),
      Geom::Point3d.new(x.mm, (y + d).mm, z.mm)
    ]
    face = ents.add_face(pts)
    face.reverse! if face.normal.z < 0
    face.pushpull(h.mm)
    paint(group, mat)
    group
  end

  # 2点間を結ぶ、先細りの丸棒を作る（脚、バー、スピンドル用）
  def self.add_bar(parent, p1_mm, p2_mm, r1_mm, r2_mm, mat, name)
    p1 = Geom::Point3d.new(p1_mm[0].mm, p1_mm[1].mm, p1_mm[2].mm)
    p2 = Geom::Point3d.new(p2_mm[0].mm, p2_mm[1].mm, p2_mm[2].mm)
    axis = p2 - p1
    axis.normalize!
    # 軸と平行でない適当なベクトルから直交基底を作る
    helper = axis.parallel?(Geom::Vector3d.new(0, 0, 1)) ? Geom::Vector3d.new(1, 0, 0) : Geom::Vector3d.new(0, 0, 1)
    u = axis.cross(helper)
    u.normalize!
    v = axis.cross(u)
    v.normalize!

    ring1 = []
    ring2 = []
    SEGMENTS.times do |i|
      angle = 2.0 * Math::PI * i / SEGMENTS
      off = Geom::Vector3d.new(
        (u.x * Math.cos(angle) + v.x * Math.sin(angle)),
        (u.y * Math.cos(angle) + v.y * Math.sin(angle)),
        (u.z * Math.cos(angle) + v.z * Math.sin(angle))
      )
      ring1 << p1.offset(off, r1_mm.mm)
      ring2 << p2.offset(off, r2_mm.mm)
    end

    group = parent.add_group
    group.name = name
    ents = group.entities
    SEGMENTS.times do |i|
      j = (i + 1) % SEGMENTS
      ents.add_face([ring1[i], ring1[j], ring2[j], ring2[i]])
    end
    ents.add_face(ring1)
    ents.add_face(ring2)
    # 辺をソフト／スムーズにして、面の継ぎ目が目立たないようにする（v2）
    ents.grep(Sketchup::Edge).each do |e|
      e.soft = true
      e.smooth = true
    end
    paint(group, mat)
    group
  end

  # 角を丸めた座面を作る（角丸の輪郭を点列で近似して押し出す）（v2）
  def self.add_rounded_seat(parent, x, y, z, w, d, h, r, mat, name)
    steps = 5 # 角ごとに円弧を何分割するか
    corners = [
      [x + w - r, y + d - r, 0],   # 右上
      [x + r, y + d - r, 90],      # 左上
      [x + r, y + r, 180],         # 左下
      [x + w - r, y + r, 270]      # 右下
    ]
    pts = []
    corners.each do |cx, cy, start_deg|
      (0..steps).each do |i|
        deg = start_deg + (90.0 * i / steps)
        rad = deg * Math::PI / 180.0
        pts << Geom::Point3d.new((cx + r * Math.cos(rad)).mm, (cy + r * Math.sin(rad)).mm, z.mm)
      end
    end
    group = parent.add_group
    group.name = name
    ents = group.entities
    face = ents.add_face(pts)
    face.reverse! if face.normal.z < 0
    face.pushpull(h.mm)
    paint(group, mat)
    group
  end

  # 背もたれ上部の板を、写真に合わせて作る（v3）
  # 形: 上の縁は中央が少し盛り上がる緩い弧、両端は丸く落とす。下の縁はほぼ直線
  # XZ平面に輪郭の面を作り、Y方向（厚み方向）へ押し出す
  def self.add_top_rail(parent, w, h, t, y_center, z_bottom, mat, name)
    r = 18.0          # 両端の丸み
    rise = 10.0       # 上縁の弧の盛り上がり（中央）
    hw = w / 2.0
    y_front = y_center + t / 2.0
    pts = []
    # 下の縁（左→右）
    pts << Geom::Point3d.new((-hw + r).mm, y_front.mm, z_bottom.mm)
    pts << Geom::Point3d.new((hw - r).mm, y_front.mm, z_bottom.mm)
    # 右端の丸み（下→上、半円状に膨らむ。中心は板の中段、半径は上下方向 h/2、横方向 r）
    1.upto(4) do |i|
      deg = -90.0 + (180.0 * i / 4)
      rad = deg * Math::PI / 180.0
      pts << Geom::Point3d.new(((hw - r) + r * Math.cos(rad)).mm, y_front.mm, (z_bottom + (h / 2.0) + (h / 2.0) * Math.sin(rad)).mm)
    end
    # 上の縁の弧（右→左、中央が rise 分だけ高い）
    1.upto(8) do |i|
      x = (hw - r) - ((w - 2 * r) * i / 8.0)
      z = z_bottom + (h - rise) + rise * (1.0 - (x / hw)**2)
      pts << Geom::Point3d.new(x.mm, y_front.mm, z.mm)
    end
    # 左端の丸み（上→下、半円状に膨らむ）
    1.upto(4) do |i|
      deg = 90.0 + (180.0 * i / 4)
      rad = deg * Math::PI / 180.0
      pts << Geom::Point3d.new(((-hw + r) + r * Math.cos(rad)).mm, y_front.mm, (z_bottom + (h / 2.0) + (h / 2.0) * Math.sin(rad)).mm)
    end
    group = parent.add_group
    group.name = name
    ents = group.entities
    face = ents.add_face(pts)
    # 面の法線が -Y になる想定で厚み分を押し出す（向きが逆でも厚みは同じ）
    face.pushpull(t.mm)
    paint(group, mat)
    group
  end

  # 脚の中心線上で、高さ z の位置を返す（脚の傾きに沿った補間）
  def self.leg_point_at(top, bottom, z)
    ratio = (top[2] - z).to_f / (top[2] - bottom[2])
    [
      top[0] + (bottom[0] - top[0]) * ratio,
      top[1] + (bottom[1] - top[1]) * ratio,
      z
    ]
  end

  def self.build
    c = CONFIG
    model = Sketchup.active_model
    model.start_operation('AMuse椅子生成', true)

    model.entities.grep(Sketchup::Group).each do |g|
      g.erase! if g.name == GROUP_NAME
    end

    tag = model.layers['自動生成_家具'] || model.layers.add('自動生成_家具')
    mat = yellow_material(model)

    root = model.entities.add_group
    root.name = GROUP_NAME
    root.layer = tag
    ents = root.entities

    seat_top = c[:seat_height_mm]
    seat_z = seat_top - c[:seat_t_mm]
    hw = c[:seat_w_mm] / 2.0   # 座面 半幅 140
    hd = c[:seat_d_mm] / 2.0   # 座面 半奥行 145

    # 座面（v2: 角を半径25mmで丸めた形）
    add_rounded_seat(ents, -hw, -hd, seat_z, c[:seat_w_mm], c[:seat_d_mm], c[:seat_t_mm], 25, mat, '座面')

    # 脚（上は座面の内側、下は外へ広がる）
    leg_top_in_x = 100
    leg_top_in_y = 105
    foot_hx = c[:foot_w_mm] / 2.0
    foot_hy = c[:foot_d_mm] / 2.0
    leg_tops = {
      front_left:  [-leg_top_in_x,  leg_top_in_y, seat_z + 5],
      front_right: [ leg_top_in_x,  leg_top_in_y, seat_z + 5],
      back_left:   [-leg_top_in_x, -leg_top_in_y, seat_z + 5],
      back_right:  [ leg_top_in_x, -leg_top_in_y, seat_z + 5]
    }
    leg_bottoms = {
      front_left:  [-foot_hx,  foot_hy, 0],
      front_right: [ foot_hx,  foot_hy, 0],
      back_left:   [-foot_hx, -foot_hy, 0],
      back_right:  [ foot_hx, -foot_hy, 0]
    }
    leg_tops.each do |key, top|
      add_bar(ents, leg_bottoms[key], top, c[:leg_bottom_r_mm], c[:leg_top_r_mm], mat, "脚_#{key}")
    end

    # 足掛けバー（前・左右・後ろの4本、脚の傾きに沿った位置で結ぶ）
    rz = c[:rung_z_mm]
    rung_pairs = [
      %i[front_left front_right],
      %i[back_left back_right],
      %i[front_left back_left],
      %i[front_right back_right]
    ]
    rung_pairs.each_with_index do |(a, b), i|
      pa = leg_point_at(leg_tops[a], leg_bottoms[a], rz)
      pb = leg_point_at(leg_tops[b], leg_bottoms[b], rz)
      add_bar(ents, pa, pb, c[:rung_r_mm], c[:rung_r_mm], mat, "足掛けバー_#{i + 1}")
    end

    # 背もたれのスピンドル4本（写真・寸法図の通り4本。座面の後ろから、少し後ろへ傾けて）
    spindle_bottom_x = [-95, -32, 32, 95]
    spindle_top_x = [-118, -40, 40, 118]
    rail_bottom_z = c[:total_height_mm] - c[:rail_h_mm]
    spindle_bottom_x.each_with_index do |bx, i|
      bottom = [bx, -hd + 25, seat_top - 5]
      top = [spindle_top_x[i], -hd - 18, rail_bottom_z + 10]
      add_bar(ents, bottom, top, c[:spindle_r_mm], c[:spindle_r_mm], mat, "背スピンドル_#{i + 1}")
    end

    # 背もたれ上部の板（v3: 上縁が緩い弧、両端が丸い形。少し後ろへ傾ける）
    rail_w = 300
    rail_group = add_top_rail(ents, rail_w, c[:rail_h_mm], c[:rail_t_mm], -hd - 18, rail_bottom_z, mat, '背もたれ上部')
    tilt_center = Geom::Point3d.new(0, (-hd - 18).mm, (rail_bottom_z + c[:rail_h_mm] / 2.0).mm)
    rail_group.transform!(Geom::Transformation.rotation(tilt_center, Geom::Vector3d.new(1, 0, 0), -8.degrees))

    model.commit_operation
    model.active_view.zoom(root)
    puts "AMuse椅子生成: 全高#{c[:total_height_mm]}mm、座面#{c[:seat_w_mm]}×#{c[:seat_d_mm]}mm（高さ#{seat_top}mm）の椅子を作りました。"
  rescue StandardError => e
    model.abort_operation
    puts "AMuse椅子生成でエラー: #{e.class}: #{e.message}"
  end
end

AMuseChair.build
