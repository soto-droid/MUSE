# AMuse 自動生成スクリプト（SketchUp Ruby）
# 使い方:
#   1. SketchUp でこのファイルを読み込む
#      - ウィンドウ > Ruby コンソール を開き、下記を実行
#        load '（このファイルのフルパス）'
#      - または 拡張機能 > 開発 > Ruby 拡張機能を読み込む 等の環境に合わせて読み込む
#   2. 読み込むと、現在のモデルに「AMuse自動生成モデル」が作られます
#   3. 寸法を変えたいときは、下の CONFIG の数字（mm）を書き換えて再読み込みしてください
#      再読み込みすると、前回作った自動生成モデルは消えて作り直されます（手作業のモデルは消えません）
#
# 生成内容:
#   - 床スラブ、4面の壁（南面にドア開口と窓開口、北面に窓開口）
#   - 屋根スラブ（フラット）
#   - 開口はブーリアンを使わず、開口の周りを箱で組み立てる方式なので失敗しにくいです
#   - 壁・床・屋根・開口まわりは別々のグループ／タグ／マテリアルに分けています
#     → Twinmotion で仕上げを分ける下準備（色分け）としても使えます

module AMuseAutoRoom
  # ===== ここだけ書き換えれば寸法が変わります（単位はすべて mm）=====
  CONFIG = {
    width_mm:        6000,  # 建物の幅（X方向）
    depth_mm:        4500,  # 建物の奥行（Y方向）
    height_mm:       2800,  # 壁の高さ（天井高）
    wall_t_mm:        150,  # 壁の厚さ
    floor_t_mm:       150,  # 床スラブの厚さ
    roof_t_mm:        200,  # 屋根スラブの厚さ
    # 南面（Y=0 側）のドア
    door_x_mm:       1000,  # ドア左端の位置（建物左端から）
    door_w_mm:        900,  # ドア幅
    door_h_mm:       2000,  # ドア高さ
    # 南面の窓
    s_window_x_mm:   3200,  # 窓左端の位置
    s_window_w_mm:   1800,  # 窓幅
    s_window_sill_mm: 800,  # 窓台の高さ
    s_window_h_mm:   1200,  # 窓の高さ
    # 北面（奥側）の窓
    n_window_x_mm:   2100,
    n_window_w_mm:   1800,
    n_window_sill_mm: 800,
    n_window_h_mm:   1200
  }.freeze

  GROUP_NAME = 'AMuse自動生成モデル'.freeze

  def self.material(model, name, red, green, blue)
    mat = model.materials[name] || model.materials.add(name)
    mat.color = Sketchup::Color.new(red, green, blue)
    mat
  end

  # 箱を1つ作る（x,y,z は最小コーナー、w,d,h は寸法。すべて mm 数値）
  # tag には Sketchup::Layer を渡すこと。グループ名にはレイヤー名の文字列を使う
  # （修正版: 以前は Layer オブジェクトをそのままグループ名に入れて TypeError になっていた）
  def self.add_box(parent_entities, x, y, z, w, d, h, mat, tag)
    return if w <= 0 || d <= 0 || h <= 0

    group = parent_entities.add_group
    group.name = tag ? tag.name.to_s : 'AMuse箱'
    group.layer = tag if tag
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
    ents.grep(Sketchup::Face).each { |f| f.material = mat; f.back_material = mat }
    group
  end

  # 開口のある壁を、開口の周りの箱の組み合わせで作る
  # openings: [{x:, w:, bottom:, top:}] 壁の左端からの位置（mm）
  def self.add_wall_with_openings(parent, horizontal:, fixed:, length:, height:, t:, openings:, mat:, tag:)
    # 開口のない帯（下・上）と、開口の間の柱で組み立てる
    sorted = openings.sort_by { |o| o[:x] }
    cursor = 0
    # まず開口の上下以外の「柱」部分（全高）
    sorted.each do |o|
      seg_w = o[:x] - cursor
      if horizontal
        add_box(parent, cursor, fixed, 0, seg_w, t, height, mat, tag)
      else
        add_box(parent, fixed, cursor, 0, t, seg_w, height, mat, tag)
      end
      # 開口の下（窓台）と上（まぐさ）
      if o[:bottom] > 0
        if horizontal
          add_box(parent, o[:x], fixed, 0, o[:w], t, o[:bottom], mat, tag)
        else
          add_box(parent, fixed, o[:x], 0, t, o[:w], o[:bottom], mat, tag)
        end
      end
      top_h = height - o[:top]
      if top_h > 0
        if horizontal
          add_box(parent, o[:x], fixed, o[:top], o[:w], t, top_h, mat, tag)
        else
          add_box(parent, fixed, o[:x], o[:top], t, o[:w], top_h, mat, tag)
        end
      end
      cursor = o[:x] + o[:w]
    end
    # 最後の柱
    seg_w = length - cursor
    if horizontal
      add_box(parent, cursor, fixed, 0, seg_w, t, height, mat, tag)
    else
      add_box(parent, fixed, cursor, 0, t, seg_w, height, mat, tag)
    end
  end

  def self.build
    c = CONFIG
    model = Sketchup.active_model
    model.start_operation('AMuse自動生成', true)

    # 前回の自動生成モデルがあれば消す（手作業のモデルには触らない）
    model.entities.grep(Sketchup::Group).each do |g|
      g.erase! if g.name == GROUP_NAME
    end

    # タグ（レイヤー）を用意
    %w[自動生成_床 自動生成_壁 自動生成_屋根].each do |name|
      model.layers.add(name) unless model.layers[name]
    end

    wall_mat  = material(model, '自動生成_壁（白）', 240, 238, 232)
    floor_mat = material(model, '自動生成_床（グレー）', 170, 170, 170)
    roof_mat  = material(model, '自動生成_屋根（濃グレー）', 110, 110, 115)

    root = model.entities.add_group
    root.name = GROUP_NAME
    ents = root.entities

    w = c[:width_mm]; d = c[:depth_mm]; h = c[:height_mm]; t = c[:wall_t_mm]

    # 床スラブ（壁の下に敷く）
    add_box(ents, 0, 0, -c[:floor_t_mm], w, d, c[:floor_t_mm], floor_mat, model.layers['自動生成_床'])

    # 南面（手前、Y=0）: ドア＋窓
    add_wall_with_openings(
      ents, horizontal: true, fixed: 0, length: w, height: h, t: t,
      openings: [
        { x: c[:door_x_mm], w: c[:door_w_mm], bottom: 0, top: c[:door_h_mm] },
        { x: c[:s_window_x_mm], w: c[:s_window_w_mm], bottom: c[:s_window_sill_mm], top: c[:s_window_sill_mm] + c[:s_window_h_mm] }
      ],
      mat: wall_mat, tag: model.layers['自動生成_壁']
    )

    # 北面（奥、Y=d-t）: 窓
    add_wall_with_openings(
      ents, horizontal: true, fixed: d - t, length: w, height: h, t: t,
      openings: [
        { x: c[:n_window_x_mm], w: c[:n_window_w_mm], bottom: c[:n_window_sill_mm], top: c[:n_window_sill_mm] + c[:n_window_h_mm] }
      ],
      mat: wall_mat, tag: model.layers['自動生成_壁']
    )

    # 西面（左、X=0）と東面（右、X=w-t）: 開口なし
    add_box(ents, 0, t, 0, t, d - (2 * t), h, wall_mat, model.layers['自動生成_壁'])
    add_box(ents, w - t, t, 0, t, d - (2 * t), h, wall_mat, model.layers['自動生成_壁'])

    # 屋根スラブ
    add_box(ents, 0, 0, h, w, d, c[:roof_t_mm], roof_mat, model.layers['自動生成_屋根'])

    model.commit_operation
    model.active_view.zoom(root)
    puts "AMuse自動生成: 幅#{w}mm × 奥行#{d}mm × 高さ#{h}mm のモデルを作りました。"
  rescue StandardError => e
    model.abort_operation
    puts "AMuse自動生成でエラー: #{e.class}: #{e.message}"
  end
end

AMuseAutoRoom.build
