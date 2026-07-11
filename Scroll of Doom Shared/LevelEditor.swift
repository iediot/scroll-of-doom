#if os(iOS)
import SwiftUI
import SpriteKit

// pixel offsets that match the game exactly (LevelScene keyRightInset/keyTopOffset)
private enum GameRef {
    static let slotRightInset: CGFloat = 35
    static let slotTopOffset: CGFloat = 419
    static var barHeight: CGFloat { GameTabBar.height }
}

// MARK: - My Levels hub (opened from the Photos app)

struct MyLevelsView: View {
    var onExit: () -> Void

    @State private var levels: [LevelData] = CustomLevelStore.load()
    @State private var editing: LevelData?
    @State private var playing: LevelData?
    @State private var showImport = false
    @State private var importText = ""
    @State private var selecting = false
    @State private var selectedIDs: Set<UUID> = []

    // photos style, three tight square columns
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        ZStack(alignment: .top) {
            Color.gameBG.ignoresSafeArea()

            // grid scrolls the full height, under the floating title
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: cols, spacing: 2) {
                        ForEach(levels) { level in
                            levelTile(level)
                        }
                        if !selecting { newTile }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.top, 150)
                    .padding(.horizontal, 2)
                    .padding(.bottom, selecting ? 100 : 40)
                }
                .onAppear {
                    DispatchQueue.main.async { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }

            header
            if selecting {
                VStack { Spacer(); selectionBar }
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(item: $editing) { level in
            LevelEditorView(level: level,
                            isNew: !levels.contains { $0.id == level.id },
                            onSave: { saved in upsert(saved) },
                            onExit: { editing = nil })
        }
        .fullScreenCover(item: $playing) { level in
            LevelPlaytestView(level: level, onExit: { playing = nil })
        }
        .alert("Paste a Level Code", isPresented: $showImport) {
            TextField("Code", text: $importText)
            Button("Import") {
                if let l = CustomLevelStore.decode(importText) { upsert(l) }
                importText = ""
            }
            Button("Cancel", role: .cancel) { importText = "" }
        }
    }

    // big photos style title, floats over the grid with a blur so its readable
    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center) {
                glassIcon("chevron.left", action: onExit)
                Spacer()
                if selecting {
                    pill("Cancel") { selecting = false; selectedIDs = [] }
                } else {
                    glassIcon("square.and.arrow.down") { showImport = true }
                    pill("Select") { selecting = true }
                }
            }
            Text("My Levels").font(.system(size: 30, weight: .bold))
            Text("\(levels.count) Items")
                .font(.subheadline).bold().foregroundStyle(.white)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 58)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // dark, subtle blur only behind the text, faded at the bottom, so the
        // title and count stay crisp and previews show through underneath
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color.black.opacity(0.55)
            }
            .mask(LinearGradient(colors: [.black, .black, .clear],
                                 startPoint: .top, endPoint: .bottom))
        }
        .ignoresSafeArea(edges: .top)
    }

    private func glassIcon(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 16, weight: .semibold))
                .frame(width: 36, height: 36)
                .glassEffect(.regular, in: Circle())
        }
        .foregroundStyle(.white)
    }

    private func pill(_ text: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.subheadline).bold()
                .padding(.horizontal, 14).frame(height: 36)
                .glassEffect(.regular, in: Capsule())
        }
        .foregroundStyle(.white)
    }

    private var selectionBar: some View {
        HStack(spacing: 16) {
            Text(selectedIDs.isEmpty ? "Select Items"
                 : "\(selectedIDs.count) Item\(selectedIDs.count == 1 ? "" : "s") Selected")
                .font(.subheadline).bold()
                .foregroundStyle(.white)
            Button(role: .destructive) {
                levels.removeAll { selectedIDs.contains($0.id) }
                CustomLevelStore.save(levels)
                selectedIDs = []
            } label: {
                Image(systemName: "trash").font(.system(size: 18))
                    .frame(width: 40, height: 40)
                    .glassEffect(.regular, in: Circle())
            }
            .disabled(selectedIDs.isEmpty)
            .opacity(selectedIDs.isEmpty ? 0.4 : 1)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 88)
        .background(.ultraThinMaterial)
    }

    private var newTile: some View {
        Button {
            editing = LevelData(name: "level \(levels.count + 1)")
        } label: {
            Color(white: 0.11)
                .aspectRatio(1, contentMode: .fill)
                .overlay(
                    VStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 26, weight: .medium))
                        Text("New").font(.caption2)
                    }
                    .foregroundStyle(.white.opacity(0.5))
                )
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
    }

    private func levelTile(_ level: LevelData) -> some View {
        let isSel = selectedIDs.contains(level.id)
        return Button {
            if selecting {
                if isSel { selectedIDs.remove(level.id) } else { selectedIDs.insert(level.id) }
            } else {
                playing = level
            }
        } label: {
            Color(white: 0.09)
                .aspectRatio(1, contentMode: .fill)
                .overlay(LevelPreview(level: level).opacity(selecting && !isSel ? 0.5 : 1))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(alignment: .bottomLeading) {
                    Text(level.name).font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white).shadow(radius: 2).padding(6)
                }
                .overlay(alignment: .bottomTrailing) {
                    if selecting {
                        Image(systemName: isSel ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18))
                            .foregroundStyle(isSel ? .white : .white.opacity(0.7))
                            .shadow(radius: 2).padding(5)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if !level.powerups.isEmpty {
                        HStack(spacing: 3) {
                            ForEach(Array(level.powerups), id: \.self) { p in
                                Image(uiImage: GameArt.icon(for: p))
                                    .resizable().scaledToFit().frame(width: 15)
                            }
                        }
                        .padding(.horizontal, 4).padding(.vertical, 3)
                        .background(.white.opacity(0.2), in: Capsule())
                        .padding(5)
                    }
                }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { editing = level } label: { Label("Edit", systemImage: "pencil") }
            Button {
                UIPasteboard.general.string = CustomLevelStore.encode(level)
            } label: { Label("Copy share code", systemImage: "doc.on.doc") }
            Button(role: .destructive) { delete(level) } label: {
                Label("Delete", systemImage: "trash")
            }
        } preview: {
            LevelPreview(level: level)
                .frame(width: 200, height: 200)
                .background(Color(white: 0.09))
        }
    }

    private func upsert(_ level: LevelData) {
        if let i = levels.firstIndex(where: { $0.id == level.id }) { levels[i] = level }
        else { levels.append(level) }
        CustomLevelStore.save(levels)
    }

    private func delete(_ level: LevelData) {
        levels.removeAll { $0.id == level.id }
        CustomLevelStore.save(levels)
    }
}

// a static mini render of the level, same look as the game minus the player
private struct LevelPreview: View {
    let level: LevelData

    private let ref = UIScreen.main.bounds.size
    private let edgeInset: CGFloat = 4

    // game point, y up, to preview point, y down
    private func point(_ x: CGFloat, _ y: CGFloat, _ f: Fit) -> CGPoint {
        CGPoint(x: f.ox + x * f.s, y: f.oy + (ref.height - y) * f.s)
    }

    private struct Fit { let s, ox, oy: CGFloat }

    private func fit(_ size: CGSize) -> Fit {
        // fill the square and crop the overflow, with the gate pinned to the bottom
        // so the useless strip below it is dropped
        let s = max(size.width / ref.width, size.height / ref.height)
        return Fit(s: s, ox: (size.width - ref.width * s) / 2,
                   oy: size.height - (ref.height - GameRef.barHeight) * s)
    }

    var body: some View {
        GeometryReader { g in
            let f = fit(g.size)
            let hp = max(7, 22 * f.s)
            ZStack(alignment: .topLeading) {
                Color(white: 0.16)
                // same ruled paper wallpaper the game uses, anchored left
                Image("level.wallpaper").resizable().scaledToFill()
                    .frame(width: g.size.width, height: g.size.height, alignment: .leading)
                Canvas { ctx, _ in draw(ctx, f) }

                // the placed heart key
                Image("cube.heart").resizable().scaledToFit().frame(width: hp * 1.3, height: hp * 1.3)
                    .position(point(CGFloat(level.heartX) * ref.width, CGFloat(level.heartY) * ref.height, f))

                playerModel(f)
            }
            .frame(width: g.size.width, height: g.size.height)
            .clipped()
        }
    }

    // the full character, powerup gear included, standing on the gate
    private func playerModel(_ f: Fit) -> some View {
        let mw = 40 * f.s, mh = mw * 600 / 512
        let ww = 60 * f.s, wh = ww * 600 / 700
        let feet = point(ref.width / 2, GameRef.barHeight, f)
        return ZStack {
            if level.powerups.contains(.doubleJump) {
                Image("cube.wings").resizable().scaledToFit()
                    .frame(width: ww, height: wh).offset(y: -mh * 0.12)
            }
            Image("cube.sitting").resizable().scaledToFit().frame(width: mw, height: mh)
            if level.powerups.contains(.dash) {
                Image("cube.shoes").resizable().scaledToFit().frame(width: mw, height: mh)
            }
            Image("cube.eyes").resizable().scaledToFit().frame(width: mw, height: mh)
            Image("cube.mouth.neutral").resizable().scaledToFit().frame(width: mw, height: mh)
        }
        .frame(width: mw, height: mh)
        .position(x: feet.x, y: feet.y - mh / 2)
    }

    private func draw(_ ctx: GraphicsContext, _ f: Fit) {
        let line = max(1.3, 3.3 * f.s)
        let rim = line * 5 / 3   // black outline all around, a third of the bar each side
        // the side walls and top are black in game, only the gate and platforms show
        let tl = point(edgeInset, ref.height - edgeInset, f)
        let br = point(ref.width - edgeInset, GameRef.barHeight, f)

        // draws a bar as a black rim under a grayer core
        func bar(_ path: Path, cap: CGLineCap) {
            ctx.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: rim, lineCap: cap))
            ctx.stroke(path, with: .color(Color(white: 0.8)), style: StrokeStyle(lineWidth: line, lineCap: cap))
        }

        // the full width gate that is the floor
        var gate = Path()
        gate.move(to: CGPoint(x: tl.x, y: br.y))
        gate.addLine(to: CGPoint(x: br.x, y: br.y))
        bar(gate, cap: .butt)

        // platforms and walls
        for p in level.platforms {
            let cx = CGFloat(p.x) * ref.width + CGFloat(p.offX)
            let cy = CGFloat(p.y) * ref.height + CGFloat(p.offY)
            let len = CGFloat(p.w) * ref.width
            var seg = Path()
            if p.isVertical {
                seg.move(to: point(cx, cy - len / 2, f)); seg.addLine(to: point(cx, cy + len / 2, f))
            } else {
                seg.move(to: point(cx - len / 2, cy, f)); seg.addLine(to: point(cx + len / 2, cy, f))
            }
            bar(seg, cap: .round)
        }
    }
}

// MARK: - Editor

struct LevelEditorView: View {
    @State var level: LevelData
    var isNew: Bool = false
    var onSave: (LevelData) -> Void
    var onExit: () -> Void

    @State private var selected: UUID?
    @State private var heartSelected = false
    @State private var multiMode = false
    @State private var multiSelected: Set<UUID> = []
    @State private var multiAnchors: [UUID: CGPoint] = [:]
    @State private var showProps = false
    @State private var showPowerups = false
    @State private var playing = false
    @State private var heartPlaced: Bool
    @State private var draggingNewPlatform: UUID?
    @State private var draggingHeart = false
    @State private var dragAnchor: CGPoint?
    @State private var canvasSize: CGSize = .zero
    private let gridCols: CGFloat = 27

    init(level: LevelData, isNew: Bool = false,
         onSave: @escaping (LevelData) -> Void, onExit: @escaping () -> Void) {
        _level = State(initialValue: level)
        self.isNew = isNew
        self.onSave = onSave
        self.onExit = onExit
        _heartPlaced = State(initialValue: !isNew)   // existing levels already have a heart
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let barY = h - GameRef.barHeight

            ZStack {
                Color.gameBG

                // gate line and the empty heart slot, drawn exactly where the game puts them
                Rectangle().fill(.white.opacity(0.35)).frame(height: 1).position(x: w / 2, y: barY)
                Image("cube.heart").resizable().scaledToFit().frame(width: 34, height: 34).opacity(0.4)
                    .position(x: w - GameRef.slotRightInset, y: GameRef.slotTopOffset)

                gridOverlay(w: w, h: h)

                Color.clear.contentShape(Rectangle())
                    .onTapGesture { selected = nil; heartSelected = false; multiSelected = [] }

                ForEach($level.platforms) { $p in platformView($p, w: w, h: h) }

                if heartPlaced || draggingHeart { heartView(w: w, h: h) }

                topBar
                paletteBar(w: w, h: h, barY: barY)
            }
            .coordinateSpace(name: "canvas")
            .onAppear { canvasSize = CGSize(width: w, height: h) }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onChange(of: selected) { _, new in if new == nil { showProps = false } }
        .sheet(isPresented: $showProps) {
            propsSheet
                .presentationDetents([.height(300)])
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showPowerups) {
            powerupsSheet
                .presentationDetents([.height(240)])
                .presentationBackground(.ultraThinMaterial)
        }
        .fullScreenCover(isPresented: $playing) {
            LevelPlaytestView(level: level, onExit: { playing = false })
        }
    }

    @ViewBuilder private var propsSheet: some View {
        if let id = selected, let i = level.platforms.firstIndex(where: { $0.id == id }) {
            let vert = level.platforms[i].isVertical
            let cells = Binding<Int>(
                get: { max(1, Int((level.platforms[i].w * gridCols).rounded())) },
                set: { n in
                    level.platforms[i].w = Double(n) / Double(gridCols)
                    let W = canvasSize.width, H = canvasSize.height
                    guard W > 0, H > 0 else { return }
                    let c = CGPoint(x: CGFloat(level.platforms[i].x) * W,
                                    y: (1 - CGFloat(level.platforms[i].y)) * H)
                    let s = snapPlatform(c, w: W, cells: n, vertical: vert)
                    level.platforms[i].x = fx(s.x, W)
                    level.platforms[i].y = fy(s.y, H)
                }
            )
            // one step per pixel across a whole cell, so maxing it lines up with the
            // next tile instead of leaving a couple unreachable pixels
            let maxOff = max(0, Int((canvasSize.width / gridCols).rounded()))
            let ox = Binding<Int>(
                get: { Int(level.platforms[i].offX) },
                set: { level.platforms[i].ox = Double($0) }
            )
            let oy = Binding<Int>(
                get: { Int(level.platforms[i].offY) },
                set: { level.platforms[i].oy = Double($0) }
            )
            VStack(alignment: .leading, spacing: 18) {
                Text("Properties").font(.title2).bold()
                propRow(vert ? "Height" : "Length", "\(cells.wrappedValue) squares", cells, 1...Int(gridCols))
                propRow("X Offset", "\(ox.wrappedValue) px", ox, 0...maxOff)
                propRow("Y Offset", "\(oy.wrappedValue) px", oy, 0...maxOff)
            }
            .foregroundStyle(.white)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func propRow(_ label: String, _ value: String, _ binding: Binding<Int>, _ range: ClosedRange<Int>) -> some View {
        HStack {
            Text(label).font(.headline)
            Spacer()
            Text(value).font(.headline).monospacedDigit().foregroundStyle(.secondary)
            Stepper("", value: binding, in: range).labelsHidden()
        }
    }

    private var powerupsSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Powerups").font(.title2).bold()
            ForEach(Powerup.allCases, id: \.self) { p in
                Toggle(isOn: powerupBinding(p)) {
                    Text(powerupName(p)).font(.headline)
                }
            }
        }
        .tint(.green)
        .foregroundStyle(.white)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func powerupBinding(_ p: Powerup) -> Binding<Bool> {
        Binding(get: { level.powerups.contains(p) },
                set: { if $0 { level.powerups.insert(p) } else { level.powerups.remove(p) } })
    }

    private func powerupName(_ p: Powerup) -> String {
        switch p {
        case .doubleJump: return "Double Jump"
        case .dash: return "Dash"
        }
    }

    private var topBar: some View {
        VStack {
            HStack(spacing: 10) {
                Button(action: exitSaving) {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                        .frame(width: 36, height: 36).glassEffect(.regular, in: Circle())
                }
                TextField("name", text: $level.name)
                    .font(.subheadline).bold().foregroundStyle(.white).frame(maxWidth: 80)
                Spacer()
                if selected != nil, !multiMode {
                    barButton("slider.horizontal.3") { showProps = true }
                }
                if selected != nil || !multiSelected.isEmpty {
                    barButton("trash", tint: .red) { deleteSelected() }
                }
                barButton(multiMode ? "checkmark.circle.fill" : "checkmark.circle",
                          tint: multiMode ? .yellow : .white) {
                    multiMode.toggle()
                    selected = nil; heartSelected = false; multiSelected = []
                }
                barButton("bolt.fill") { showPowerups = true }
                barButton("play.fill") { playing = true }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.top, 58)
            Spacer()
        }
    }

    private func barButton(_ name: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 15, weight: .semibold))
                .frame(width: 36, height: 36).glassEffect(.regular, in: Circle())
        }
        .foregroundStyle(tint)
    }

    // sits where the control bar will be and looks like it, drag items out of it
    private func paletteBar(w: CGFloat, h: CGFloat, barY: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 0) {
                Rectangle().fill(.white.opacity(0.15)).frame(height: 0.5)
                HStack(spacing: 40) {
                    platformPaletteItem(vertical: false, w: w, h: h)
                    platformPaletteItem(vertical: true, w: w, h: h)

                    Image("cube.heart").resizable().scaledToFit().frame(width: 30, height: 30)
                        .opacity(heartPlaced ? 0.3 : 1)
                        .frame(width: 64, height: 44).contentShape(Rectangle())
                        .allowsHitTesting(!heartPlaced)
                        .gesture(DragGesture(coordinateSpace: .named("canvas"))
                            .onChanged { v in
                                draggingHeart = true
                                let s = snap(v.location, w: w, h: h)
                                level.heartX = fx(s.x, w)
                                level.heartY = fy(s.y, h)
                            }
                            .onEnded { _ in draggingHeart = false; heartPlaced = true; selected = nil })
                }
                .padding(.top, 16)
                Spacer()
            }
            .frame(height: GameRef.barHeight)
            .background(Color.gameBG)
        }
    }

    // a draggable platform icon in the palette, horizontal or vertical
    private func platformPaletteItem(vertical: Bool, w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            Capsule().fill(.black)
                .frame(width: vertical ? 7.7 : 49, height: vertical ? 43 : 7.7)
            Capsule().fill(Color(white: 0.8))
                .frame(width: vertical ? 4.4 : 46, height: vertical ? 40 : 4.4)
        }
            .frame(width: 56, height: 46).contentShape(Rectangle())
            .gesture(DragGesture(coordinateSpace: .named("canvas"))
                .onChanged { v in
                    let cells = vertical ? 4 : 5
                    let s = snapPlatform(v.location, w: w, cells: cells, vertical: vertical)
                    if let id = draggingNewPlatform, let i = level.platforms.firstIndex(where: { $0.id == id }) {
                        level.platforms[i].x = fx(s.x, w)
                        level.platforms[i].y = fy(s.y, h)
                    } else {
                        let p = PlatformData(x: fx(s.x, w), y: fy(s.y, h),
                                             w: Double(cells) / Double(gridCols), vertical: vertical ? true : nil)
                        level.platforms.append(p)
                        draggingNewPlatform = p.id
                        selected = p.id
                    }
                }
                .onEnded { _ in draggingNewPlatform = nil })
    }

    private func platformView(_ p: Binding<PlatformData>, w: CGFloat, h: CGFloat) -> some View {
        let id = p.wrappedValue.id
        let isSel = multiMode ? multiSelected.contains(id) : selected == id
        let cx = CGFloat(p.wrappedValue.x) * w + CGFloat(p.wrappedValue.offX)
        let cy = (1 - CGFloat(p.wrappedValue.y)) * h - CGFloat(p.wrappedValue.offY)
        let len = CGFloat(p.wrappedValue.w) * w
        let vert = p.wrappedValue.isVertical
        return ZStack {
            // black rim all around, grayer bar on top, matching the game
            Capsule().fill(.black)
                .frame(width: vert ? 5.5 : len + 2.2, height: vert ? len + 2.2 : 5.5)
            Capsule().fill(isSel ? Color.yellow : Color(white: 0.8))
                .frame(width: vert ? 3.3 : len, height: vert ? len : 3.3)
        }
            .frame(width: vert ? 30 : max(len, 44), height: vert ? max(len, 44) : 30)
            .contentShape(Rectangle())
            .position(x: cx, y: cy)
            .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("canvas"))
                .onChanged { v in
                    if multiMode {
                        if multiAnchors.isEmpty {
                            multiSelected.insert(id)
                            for sid in multiSelected {
                                if let q = level.platforms.first(where: { $0.id == sid }) {
                                    multiAnchors[sid] = CGPoint(x: CGFloat(q.x) * w, y: (1 - CGFloat(q.y)) * h)
                                }
                            }
                        }
                        moveGroup(translation: v.translation, w: w, h: h)
                    } else {
                        if dragAnchor == nil {
                            selected = id; heartSelected = false
                            // grid position without the sub-cell offset, so snapping stays clean
                            dragAnchor = CGPoint(x: CGFloat(p.wrappedValue.x) * w,
                                                 y: (1 - CGFloat(p.wrappedValue.y)) * h)
                        }
                        guard let a = dragAnchor else { return }
                        let cells = max(1, Int((p.wrappedValue.w * gridCols).rounded()))
                        let s = snapPlatform(CGPoint(x: a.x + v.translation.width, y: a.y + v.translation.height),
                                             w: w, cells: cells, vertical: vert)
                        p.wrappedValue.x = fx(s.x, w)
                        p.wrappedValue.y = fy(s.y, h)
                    }
                }
                .onEnded { _ in dragAnchor = nil; multiAnchors = [:] })
            .onTapGesture {
                if multiMode {
                    if multiSelected.contains(id) { multiSelected.remove(id) } else { multiSelected.insert(id) }
                } else {
                    selected = id; heartSelected = false
                }
            }
    }

    // drag every selected platform by the same finger translation, each snapped to grid
    private func moveGroup(translation: CGSize, w: CGFloat, h: CGFloat) {
        for sid in multiSelected {
            guard let a = multiAnchors[sid], let i = level.platforms.firstIndex(where: { $0.id == sid }) else { continue }
            let cells = max(1, Int((level.platforms[i].w * gridCols).rounded()))
            let s = snapPlatform(CGPoint(x: a.x + translation.width, y: a.y + translation.height),
                                 w: w, cells: cells, vertical: level.platforms[i].isVertical)
            level.platforms[i].x = fx(s.x, w)
            level.platforms[i].y = fy(s.y, h)
        }
    }

    private func heartView(w: CGFloat, h: CGFloat) -> some View {
        let cx = CGFloat(level.heartX) * w, cy = (1 - CGFloat(level.heartY)) * h
        return Image("cube.heart").resizable().scaledToFit().frame(width: 34, height: 34)
            .colorMultiply(heartSelected ? .yellow : .white)
            .shadow(color: .black.opacity(0.6), radius: 3)
            .frame(width: 44, height: 44).contentShape(Rectangle())
            .position(x: cx, y: cy)
            .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("canvas"))
                .onChanged { v in
                    if dragAnchor == nil { heartSelected = true; selected = nil; dragAnchor = CGPoint(x: cx, y: cy) }
                    guard let a = dragAnchor else { return }
                    let s = snap(CGPoint(x: a.x + v.translation.width, y: a.y + v.translation.height), w: w, h: h)
                    level.heartX = fx(s.x, w)
                    level.heartY = fy(s.y, h)
                }
                .onEnded { _ in dragAnchor = nil })
            .onTapGesture { heartSelected = true; selected = nil }
    }

    // faint square grid the items snap to
    private func gridOverlay(w: CGFloat, h: CGFloat) -> some View {
        let cell = w / gridCols
        return Canvas { ctx, size in
            var x: CGFloat = 0
            while x <= size.width {
                ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) },
                           with: .color(.white.opacity(0.14)), lineWidth: 0.5)
                x += cell
            }
            var y: CGFloat = 0
            while y <= size.height {
                ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) },
                           with: .color(.white.opacity(0.14)), lineWidth: 0.5)
                y += cell
            }
        }
        .allowsHitTesting(false)
    }

    // snap a screen point to the nearest grid intersection
    private func snap(_ p: CGPoint, w: CGFloat, h: CGFloat) -> CGPoint {
        let cell = w / gridCols
        return CGPoint(x: (p.x / cell).rounded() * cell, y: (p.y / cell).rounded() * cell)
    }

    // snap a bar so both its ends land on grid lines, along its long axis, and
    // its thin axis sits on a line too
    private func snapPlatform(_ center: CGPoint, w: CGFloat, cells: Int, vertical: Bool) -> CGPoint {
        let cell = w / gridCols
        let half = CGFloat(cells) * cell / 2
        func line(_ c: CGFloat) -> CGFloat { (c / cell).rounded() * cell }
        func edge(_ c: CGFloat) -> CGFloat { ((c - half) / cell).rounded() * cell + half }
        return vertical ? CGPoint(x: line(center.x), y: edge(center.y))
                        : CGPoint(x: edge(center.x), y: line(center.y))
    }

    private func delete(_ id: UUID) {
        level.platforms.removeAll { $0.id == id }
        selected = nil
    }

    private func deleteSelected() {
        if multiMode, !multiSelected.isEmpty {
            level.platforms.removeAll { multiSelected.contains($0.id) }
            multiSelected = []
        } else if let id = selected {
            delete(id)
        }
    }

    private func exitSaving() {
        onSave(level)
        onExit()
    }

    // screen point to level fraction, kept above the tab bar
    private func fx(_ x: CGFloat, _ w: CGFloat) -> Double { clamp(Double(x / w), 0.04, 0.96) }
    private func fy(_ y: CGFloat, _ h: CGFloat) -> Double {
        clamp(Double(1 - y / h), Double(GameRef.barHeight / h) + 0.015, 0.97)
    }
    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }
}

// MARK: - Playtest

struct LevelPlaytestView: View {
    let level: LevelData
    var onExit: () -> Void

    @State private var scene: LevelScene
    @State private var gateUnlocked = false
    @State private var jumpReady = true
    @State private var airJumpReady = false
    @State private var dashReady = true
    @State private var heldDirection: CGFloat = 0

    init(level: LevelData, onExit: @escaping () -> Void) {
        self.level = level
        self.onExit = onExit
        // real screen size like the game, so the gate lands at the bar top
        let s = LevelScene(size: UIScreen.main.bounds.size)
        s.customLevel = level
        s.bottomInset = GameTabBar.height
        if level.powerups.contains(.doubleJump) { s.extraJumps = 1 }
        if level.powerups.contains(.dash) { s.hasDash = true }
        _scene = State(initialValue: s)
    }

    // composed exactly like the game feed so the gate and bar line up identically
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.gameBG
            SpriteView(scene: scene, preferredFramesPerSecond: 120,
                       options: [.ignoresSiblingOrder])
                .ignoresSafeArea()
            Button(action: onExit) {
                Image(systemName: "chevron.left").font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white).shadow(radius: 3).padding(24)
            }
            .padding(.top, 54)
        }
        .overlay(alignment: .bottom) {
            GameTabBar(gateUnlocked: gateUnlocked,
                       dashEnabled: level.powerups.contains(.dash), dashReady: dashReady,
                       wingsEnabled: level.powerups.contains(.doubleJump),
                       jumpReady: jumpReady, airJumpReady: airJumpReady,
                       onMove: { scene.setMove($0) },
                       onJump: { scene.jump() },
                       onDash: { scene.dash() })
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onAppear {
            scene.onHatchOpened = { gateUnlocked = true }
            scene.onJumpStateChanged = { jumpReady = $0; airJumpReady = $1 }
            scene.onDashStateChanged = { dashReady = $0 }
            // beating the level just restarts it for testing
            scene.onFellThrough = { _ in
                gateUnlocked = false
                scene.reload()
            }
        }
    }
}
#endif
