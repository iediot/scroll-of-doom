#if os(iOS)
import SwiftUI
import SpriteKit

// pixel offsets that match the game exactly (LevelScene keyRightInset/keyTopOffset)
private enum GameRef {
    static let slotRightInset: CGFloat = 35
    static let slotTopOffset: CGFloat = 419
    static var barHeight: CGFloat { GameTabBar.height }
}

// an upward triangle, the spike hazard
struct SpikeShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
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
                    .padding(.top, 168)
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
            VStack(alignment: .leading, spacing: 2) {
                Text("My Levels").font(.system(size: 30, weight: .bold))
                Text("\(levels.count) Items").font(.subheadline).bold()
            }
            .wordBlur()
            .padding(.top, 10)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 58)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        // progressive glass blur, blurriest at the top and easing to nothing
        .background { ProgressiveHeaderBlur() }
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
                // flatten each preview into one texture so the grid is cheap to composite
                // and blur during the open and close transitions
                .overlay(LevelPreview(level: level).drawingGroup().opacity(selecting && !isSel ? 0.5 : 1))
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

                // coins
                ForEach(level.coins) { coin in
                    Image(uiImage: GameArt.coinStillImage()).resizable().scaledToFit()
                        .frame(width: hp, height: hp)
                        .position(point(CGFloat(coin.x) * ref.width, CGFloat(coin.y) * ref.height, f))
                }

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
            if level.powerups.contains(.dash) || level.powerups.contains(.spikeBoots) {
                let dash = level.powerups.contains(.dash)
                let spike = level.powerups.contains(.spikeBoots)
                Image((dash && spike) ? "cube.boots.both" : spike ? "cube.boots.spike" : "cube.boots.dash")
                    .resizable().scaledToFit().frame(width: mw, height: mh)
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

        // spikes first so the platform bars draw over their bases
        let ordered = level.platforms.filter { $0.isSpike } + level.platforms.filter { !$0.isSpike }
        for p in ordered {
            let cx = CGFloat(p.x) * ref.width + CGFloat(p.offX)
            let cy = CGFloat(p.y) * ref.height + CGFloat(p.offY)
            let len = CGFloat(p.w) * ref.width
            let rad = CGFloat(p.rotation) * .pi / 180
            // rotate a game point about the item center then map to the tile
            func spin(_ gx: CGFloat, _ gy: CGFloat) -> CGPoint {
                if rad == 0 { return point(gx, gy, f) }
                let dx = gx - cx, dy = gy - cy
                return point(cx + dx * cos(rad) + dy * sin(rad), cy - dx * sin(rad) + dy * cos(rad), f)
            }
            if p.isSpike {
                let bb = max(len - LevelScene.spikeRimInset, len * 0.4)
                let hh = bb * LevelScene.spikeHeightRatio
                let baseY = cy - len / 2 + LevelScene.spikeGroundLift   // base lifted onto the platform
                var tri = Path()
                tri.move(to: spin(cx - bb / 2, baseY))
                tri.addLine(to: spin(cx, baseY + hh))
                tri.addLine(to: spin(cx + bb / 2, baseY))
                tri.closeSubpath()
                // black rim, grayer fill, gray edge, same as the bars
                ctx.stroke(tri, with: .color(.black), style: StrokeStyle(lineWidth: rim, lineJoin: .round))
                ctx.fill(tri, with: .color(Color(white: 0.8)))
                ctx.stroke(tri, with: .color(Color(white: 0.8)), style: StrokeStyle(lineWidth: line, lineJoin: .round))
                continue
            }
            var seg = Path()
            if p.isVertical {
                seg.move(to: spin(cx, cy - len / 2)); seg.addLine(to: spin(cx, cy + len / 2))
            } else {
                seg.move(to: spin(cx - len / 2, cy)); seg.addLine(to: spin(cx + len / 2, cy))
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
    @State private var selectedCoin: UUID?
    @State private var draggingNewCoin: UUID?
    @State private var heartSelected = false
    @State private var multiMode = false
    @State private var multiSelected: Set<UUID> = []
    @State private var multiAnchors: [UUID: CGPoint] = [:]
    @State private var showProps = false
    @State private var showPowerups = false
    @State private var showRotate = false
    @State private var rotateText = ""
    @State private var playing = false
    @State private var heartPlaced: Bool
    @State private var draggingNewPlatform: UUID?
    @State private var draggingHeart = false
    @State private var dragAnchor: CGPoint?
    @State private var canvasSize: CGSize = .zero
    @State private var zoom: CGFloat = 1
    @State private var zoomBase: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panBase: CGSize = .zero
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

                // the zoomable / pannable canvas, controls stay fixed on top
                ZStack {
                    Color.gameBG

                    // gate line and the empty heart slot, drawn where the game puts them
                    Rectangle().fill(.white.opacity(0.35)).frame(height: 1).position(x: w / 2, y: barY)
                    Image("cube.heart").resizable().scaledToFit().frame(width: 34, height: 34).opacity(0.4)
                        .position(x: w - GameRef.slotRightInset, y: GameRef.slotTopOffset)

                    gridOverlay(w: w, h: h)

                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { selected = nil; heartSelected = false; multiSelected = []; selectedCoin = nil }
                        .gesture(DragGesture(coordinateSpace: .named("screen"))
                            .onChanged { v in
                                guard zoom > 1 else { return }
                                pan = clampPan(CGSize(width: panBase.width + v.translation.width,
                                                      height: panBase.height + v.translation.height), w, h)
                            }
                            .onEnded { _ in panBase = pan })

                    ForEach($level.platforms) { $p in platformView($p, w: w, h: h) }
                    ForEach($level.coins) { $c in coinView($c, w: w, h: h) }

                    if heartPlaced || draggingHeart { heartView(w: w, h: h) }
                }
                .coordinateSpace(name: "canvas")
                .scaleEffect(zoom)
                .offset(pan)
                .clipped()
                .simultaneousGesture(MagnifyGesture()
                    .onChanged { v in
                        // zoom toward the pinch point, keeping it fixed under the fingers
                        let z1 = min(max(zoomBase * v.magnification, 1), 4)
                        let focalX = v.startAnchor.x * w, focalY = v.startAnchor.y * h
                        let cx = w / 2, cy = h / 2, r = z1 / zoomBase
                        zoom = z1
                        pan = clampPan(CGSize(width: (focalX - cx) - (focalX - cx - panBase.width) * r,
                                              height: (focalY - cy) - (focalY - cy - panBase.height) * r), w, h)
                    }
                    .onEnded { _ in
                        zoomBase = zoom
                        if zoom <= 1.001 { pan = .zero; panBase = .zero }
                        else { pan = clampPan(pan, w, h); panBase = pan }
                    })

                topBar
                paletteBar(w: w, h: h, barY: barY)
            }
            .coordinateSpace(name: "screen")
            .onAppear { canvasSize = CGSize(width: w, height: h) }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onChange(of: selected) { _, new in if new == nil, multiSelected.isEmpty { showProps = false } }
        .onChange(of: multiSelected) { _, s in if s.isEmpty, selected == nil { showProps = false } }
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

    // indices of every item the properties apply to, one or the whole selection
    private func propsTargets() -> [Int] {
        if multiMode, !multiSelected.isEmpty {
            return level.platforms.indices.filter { multiSelected.contains(level.platforms[$0].id) }
        } else if let id = selected {
            return level.platforms.indices.filter { level.platforms[$0].id == id }
        }
        return []
    }

    @ViewBuilder private var propsSheet: some View {
        let targets = propsTargets()
        if let first = targets.first {
            let vert = level.platforms[first].isVertical
            let spike = level.platforms[first].isSpike
            // length in half cells, so it steps 0.5, 1, 1.5, 2 ... applied to all
            let halves = Binding<Int>(
                get: { max(1, Int((level.platforms[first].w * gridCols * 2).rounded())) },
                set: { n in
                    let W = canvasSize.width, H = canvasSize.height
                    for i in targets {
                        level.platforms[i].w = Double(n) / (2 * Double(gridCols))
                        guard W > 0, H > 0 else { continue }
                        let c = CGPoint(x: CGFloat(level.platforms[i].x) * W,
                                        y: (1 - CGFloat(level.platforms[i].y)) * H)
                        let s = snapPlatform(c, w: W, lengthCells: CGFloat(n) / 2,
                                             vertical: level.platforms[i].isVertical,
                                             spike: level.platforms[i].isSpike)
                        level.platforms[i].x = fx(s.x, W)
                        level.platforms[i].y = fy(s.y, H)
                    }
                }
            )
            // one step per pixel across a whole cell, so maxing it lines up with the
            // next tile instead of leaving a couple unreachable pixels
            let maxOff = max(0, Int((canvasSize.width / gridCols).rounded()))
            let ox = Binding<Int>(
                get: { Int(level.platforms[first].offX) },
                set: { v in for i in targets { level.platforms[i].ox = Double(v) } }
            )
            let oy = Binding<Int>(
                get: { Int(level.platforms[first].offY) },
                set: { v in for i in targets { level.platforms[i].oy = Double(v) } }
            )
            VStack(alignment: .leading, spacing: 18) {
                Text(targets.count > 1 ? "Properties · \(targets.count)" : "Properties")
                    .font(.title2).bold()
                propRow(spike ? "Size" : (vert ? "Height" : "Length"),
                        String(format: "%g squares", Double(halves.wrappedValue) / 2),
                        halves, 1...Int(gridCols * 2))
                propRow("X Offset", "\(ox.wrappedValue) px", ox, 0...maxOff)
                propRow("Y Offset", "\(oy.wrappedValue) px", oy, 0...maxOff)
                rotationRow(Int(level.platforms[first].rotation))
            }
            .foregroundStyle(.white)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .alert("Rotation", isPresented: $showRotate) {
                TextField("1 - 359", text: $rotateText).keyboardType(.numberPad)
                Button("Set") { applyRotation() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Degrees clockwise, 1 to 359") }
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

    // opens a typed prompt for the rotation degrees
    private func rotationRow(_ current: Int) -> some View {
        Button {
            rotateText = current == 0 ? "" : "\(current)"
            showRotate = true
        } label: {
            HStack {
                Text("Rotation").font(.headline)
                Spacer()
                Text("\(current)°").font(.headline).monospacedDigit().foregroundStyle(.secondary)
                Image(systemName: "pencil").font(.system(size: 14)).foregroundStyle(.secondary)
            }
            .frame(height: 32)   // matches the height the stepper rows get
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private func applyRotation() {
        let v = Int(rotateText.trimmingCharacters(in: .whitespaces)) ?? 0
        let deg = v <= 0 ? 0 : min(v, 359)
        for i in propsTargets() { level.platforms[i].rot = deg == 0 ? nil : Double(deg) }
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

    private func powerupName(_ p: Powerup) -> String { p.title }

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
                if selected != nil || !multiSelected.isEmpty {
                    barButton("slider.horizontal.3") { showProps = true }
                    barButton("plus.square.on.square") { duplicateSelected() }
                    barButton("trash", tint: .red) { deleteSelected() }
                } else if selectedCoin != nil {
                    barButton("trash", tint: .red) {
                        level.coins.removeAll { $0.id == selectedCoin }
                        selectedCoin = nil
                    }
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
                HStack(spacing: 22) {
                    platformPaletteItem(vertical: false, w: w, h: h)
                    platformPaletteItem(vertical: true, w: w, h: h)
                    platformPaletteItem(spike: true, w: w, h: h)
                    coinPaletteItem(w: w, h: h)

                    Image("cube.heart").resizable().scaledToFit().frame(width: 30, height: 30)
                        .opacity(heartPlaced ? 0.3 : 1)
                        .frame(width: 64, height: 44).contentShape(Rectangle())
                        .allowsHitTesting(!heartPlaced)
                        .gesture(DragGesture(coordinateSpace: .named("screen"))
                            .onChanged { v in
                                draggingHeart = true
                                let s = snap(toCanvas(v.location, w, h), w: w, h: h)
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

    // drag out coins from the palette, each drop is a new coin
    private func coinPaletteItem(w: CGFloat, h: CGFloat) -> some View {
        Image(uiImage: GameArt.coinStillImage()).resizable().scaledToFit().frame(width: 26, height: 26)
            .frame(width: 44, height: 46).contentShape(Rectangle())
            .gesture(DragGesture(coordinateSpace: .named("screen"))
                .onChanged { v in
                    let s = snap(toCanvas(v.location, w, h), w: w, h: h)
                    if let id = draggingNewCoin, let i = level.coins.firstIndex(where: { $0.id == id }) {
                        level.coins[i].x = fx(s.x, w)
                        level.coins[i].y = fy(s.y, h)
                    } else {
                        let coin = CoinData(x: fx(s.x, w), y: fy(s.y, h))
                        level.coins.append(coin)
                        draggingNewCoin = coin.id
                        selectedCoin = coin.id; selected = nil; heartSelected = false
                    }
                }
                .onEnded { _ in draggingNewCoin = nil })
    }

    // a draggable icon in the palette, a horizontal bar, a wall, or a spike
    private func platformPaletteItem(vertical: Bool = false, spike: Bool = false,
                                     w: CGFloat, h: CGFloat) -> some View {
        Group {
            if spike {
                ZStack {
                    SpikeShape().fill(.black)
                        .overlay(SpikeShape().stroke(.black, style: StrokeStyle(lineWidth: 4, lineJoin: .round)))
                    SpikeShape().fill(Color(white: 0.8))
                        .overlay(SpikeShape().stroke(Color(white: 0.8), style: StrokeStyle(lineWidth: 2.4, lineJoin: .round)))
                }
                .frame(width: 30, height: 27)
            } else {
                ZStack {
                    Capsule().fill(.black)
                        .frame(width: vertical ? 7.7 : 49, height: vertical ? 43 : 7.7)
                    Capsule().fill(Color(white: 0.8))
                        .frame(width: vertical ? 4.4 : 46, height: vertical ? 40 : 4.4)
                }
            }
        }
            .frame(width: 52, height: 46).contentShape(Rectangle())
            .gesture(DragGesture(coordinateSpace: .named("screen"))
                .onChanged { v in
                    let cells = spike ? 1 : (vertical ? 4 : 5)
                    let s = snapPlatform(toCanvas(v.location, w, h), w: w, lengthCells: CGFloat(cells),
                                         vertical: vertical, spike: spike)
                    if let id = draggingNewPlatform, let i = level.platforms.firstIndex(where: { $0.id == id }) {
                        level.platforms[i].x = fx(s.x, w)
                        level.platforms[i].y = fy(s.y, h)
                    } else {
                        let p = PlatformData(x: fx(s.x, w), y: fy(s.y, h),
                                             w: Double(cells) / Double(gridCols),
                                             vertical: vertical ? true : nil, spike: spike ? true : nil)
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
        let spike = p.wrappedValue.isSpike
        let spikeBase = max(len - LevelScene.spikeRimInset, len * 0.4)
        let spikeH = spikeBase * LevelScene.spikeHeightRatio
        return Group {
            if spike {
                // black rim then grayer fill, sat at the bottom of its cell so it rotates
                // about the cell center, a tight triangle hit shape
                ZStack {
                    SpikeShape().fill(.black)
                        .overlay(SpikeShape().stroke(.black, style: StrokeStyle(lineWidth: 5.5, lineJoin: .round)))
                    SpikeShape().fill(isSel ? Color.yellow : Color(white: 0.8))
                        .overlay(SpikeShape().stroke(isSel ? Color.yellow : Color(white: 0.8),
                                                     style: StrokeStyle(lineWidth: 3.3, lineJoin: .round)))
                }
                .frame(width: spikeBase, height: spikeH)
                .padding(.bottom, LevelScene.spikeGroundLift)   // sit on the platform, not sunk in
                .frame(width: len, height: len, alignment: .bottom)
                .contentShape(Rectangle())   // whole cell grabbable so it's easy to move
            } else {
                // black rim all around, grayer bar on top, matching the game
                ZStack {
                    Capsule().fill(.black)
                        .frame(width: vert ? 5.5 : len + 2.2, height: vert ? len + 2.2 : 5.5)
                    Capsule().fill(isSel ? Color.yellow : Color(white: 0.8))
                        .frame(width: vert ? 3.3 : len, height: vert ? len : 3.3)
                }
                .frame(width: vert ? 14 : len, height: vert ? len : 14)
                .contentShape(Rectangle())
            }
        }
            .rotationEffect(.degrees(p.wrappedValue.rotation))
            .zIndex(spike ? 0 : 1)   // platform outlines read over spike bases
            .position(x: cx, y: cy)
            .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("screen"))
                .onChanged { v in
                    // screen translation to canvas translation, so zoom doesnt change the speed
                    let t = CGSize(width: v.translation.width / zoom, height: v.translation.height / zoom)
                    if multiMode {
                        if multiAnchors.isEmpty {
                            multiSelected.insert(id)
                            for sid in multiSelected {
                                if let q = level.platforms.first(where: { $0.id == sid }) {
                                    multiAnchors[sid] = CGPoint(x: CGFloat(q.x) * w, y: (1 - CGFloat(q.y)) * h)
                                }
                            }
                        }
                        moveGroup(translation: t, w: w, h: h)
                    } else {
                        if dragAnchor == nil {
                            selected = id; heartSelected = false
                            // grid position without the sub-cell offset, so snapping stays clean
                            dragAnchor = CGPoint(x: CGFloat(p.wrappedValue.x) * w,
                                                 y: (1 - CGFloat(p.wrappedValue.y)) * h)
                        }
                        guard let a = dragAnchor else { return }
                        let lc = CGFloat(p.wrappedValue.w) * gridCols
                        let s = snapPlatform(CGPoint(x: a.x + t.width, y: a.y + t.height),
                                             w: w, lengthCells: lc, vertical: vert, spike: spike)
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

    // move the whole selection by one shared whole cell delta, so mixed item types
    // keep their relative positions instead of each snapping to its own grid
    private func moveGroup(translation: CGSize, w: CGFloat, h: CGFloat) {
        let cell = w / gridCols
        let dx = (translation.width / cell).rounded() * cell
        let dy = (translation.height / cell).rounded() * cell
        for sid in multiSelected {
            guard let a = multiAnchors[sid], let i = level.platforms.firstIndex(where: { $0.id == sid }) else { continue }
            level.platforms[i].x = fx(a.x + dx, w)
            level.platforms[i].y = fy(a.y + dy, h)
        }
    }

    private func coinView(_ c: Binding<CoinData>, w: CGFloat, h: CGFloat) -> some View {
        let id = c.wrappedValue.id
        let cx = CGFloat(c.wrappedValue.x) * w, cy = (1 - CGFloat(c.wrappedValue.y)) * h
        return Image(uiImage: GameArt.coinStillImage()).resizable().scaledToFit()
            .frame(width: 24, height: 24)
            .overlay(Circle().stroke(.yellow, lineWidth: selectedCoin == id ? 2 : 0).padding(-2))
            .frame(width: 40, height: 40).contentShape(Circle())
            .position(x: cx, y: cy)
            .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("screen"))
                .onChanged { v in
                    if dragAnchor == nil {
                        selectedCoin = id; selected = nil; heartSelected = false
                        dragAnchor = CGPoint(x: cx, y: cy)
                    }
                    guard let a = dragAnchor else { return }
                    let s = snap(CGPoint(x: a.x + v.translation.width / zoom, y: a.y + v.translation.height / zoom), w: w, h: h)
                    c.wrappedValue.x = fx(s.x, w)
                    c.wrappedValue.y = fy(s.y, h)
                }
                .onEnded { _ in dragAnchor = nil })
            .onTapGesture { selectedCoin = id; selected = nil; heartSelected = false }
    }

    private func heartView(w: CGFloat, h: CGFloat) -> some View {
        let cx = CGFloat(level.heartX) * w, cy = (1 - CGFloat(level.heartY)) * h
        return Image("cube.heart").resizable().scaledToFit().frame(width: 34, height: 34)
            .colorMultiply(heartSelected ? .yellow : .white)
            .shadow(color: .black.opacity(0.6), radius: 3)
            .frame(width: 44, height: 44).contentShape(Rectangle())
            .position(x: cx, y: cy)
            .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("screen"))
                .onChanged { v in
                    if dragAnchor == nil { heartSelected = true; selected = nil; dragAnchor = CGPoint(x: cx, y: cy) }
                    guard let a = dragAnchor else { return }
                    let s = snap(CGPoint(x: a.x + v.translation.width / zoom, y: a.y + v.translation.height / zoom), w: w, h: h)
                    level.heartX = fx(s.x, w)
                    level.heartY = fy(s.y, h)
                }
                .onEnded { _ in dragAnchor = nil })
            .onTapGesture { heartSelected = true; selected = nil }
    }

    // faint square grid the items snap to
    // vertical phase so a grid line lands exactly on the gate instead of mid cell
    private func gridPhaseY(_ w: CGFloat, _ h: CGFloat) -> CGFloat {
        let cell = w / gridCols
        let barY = h - GameRef.barHeight
        return barY.truncatingRemainder(dividingBy: cell)
    }

    private func gridOverlay(w: CGFloat, h: CGFloat) -> some View {
        let cell = w / gridCols
        let py = gridPhaseY(w, h)
        return Canvas { ctx, size in
            var x: CGFloat = 0
            while x <= size.width {
                ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) },
                           with: .color(.white.opacity(0.14)), lineWidth: 0.5)
                x += cell
            }
            var y: CGFloat = py
            while y <= size.height {
                ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) },
                           with: .color(.white.opacity(0.14)), lineWidth: 0.5)
                y += cell
            }
        }
        .allowsHitTesting(false)
    }

    // snap a screen point to the nearest grid intersection, the y grid anchored to the gate
    private func snap(_ p: CGPoint, w: CGFloat, h: CGFloat) -> CGPoint {
        let cell = w / gridCols
        let py = gridPhaseY(w, h)
        return CGPoint(x: (p.x / cell).rounded() * cell,
                       y: ((p.y - py) / cell).rounded() * cell + py)
    }

    // snap a bar so its near end lands on a grid line, along its long axis, and its
    // thin axis sits on a line too, length is in cells and can be a half. the x grid
    // starts at the left edge, the y grid at the gate line
    private func snapPlatform(_ center: CGPoint, w: CGFloat, lengthCells: CGFloat,
                              vertical: Bool, spike: Bool = false) -> CGPoint {
        let cell = w / gridCols
        let py = canvasSize.height > 0 ? gridPhaseY(w, canvasSize.height) : 0
        let half = lengthCells * cell / 2
        func line(_ c: CGFloat, _ ph: CGFloat) -> CGFloat { ((c - ph) / cell).rounded() * cell + ph }
        // either edge may land on a grid line, whichever the drag is nearer to, so a
        // half length bar can start on a block or end on one
        func edge(_ c: CGFloat, _ ph: CGFloat) -> CGFloat {
            let near = ((c - half - ph) / cell).rounded() * cell + half + ph
            let far = ((c + half - ph) / cell).rounded() * cell - half + ph
            return abs(near - c) <= abs(far - c) ? near : far
        }
        if spike {
            // the pivot is the cell center, size/2 above the base, so snapping the base
            // to a grid line is the same for any rotation and keeps it in the same cell
            let sizePts = lengthCells * cell
            let baseLine = line(center.y + sizePts / 2, py)
            return CGPoint(x: edge(center.x, 0), y: baseLine - sizePts / 2)
        }
        return vertical ? CGPoint(x: line(center.x, 0), y: edge(center.y, py))
                        : CGPoint(x: edge(center.x, 0), y: line(center.y, py))
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

    // clones the selected items a cell down and right, then selects the clones
    private func duplicateSelected() {
        let dx = 1.0 / Double(gridCols)
        let dy = canvasSize.height > 0 ? Double(canvasSize.width / gridCols / canvasSize.height) : dx
        func clone(_ p: PlatformData) -> PlatformData {
            var c = p
            c.id = UUID()
            c.x = min(0.96, p.x + dx)
            c.y = max(0.04, p.y - dy)
            return c
        }
        if multiMode, !multiSelected.isEmpty {
            let copies = level.platforms.filter { multiSelected.contains($0.id) }.map(clone)
            level.platforms.append(contentsOf: copies)
            multiSelected = Set(copies.map { $0.id })
        } else if let id = selected, let p = level.platforms.first(where: { $0.id == id }) {
            let c = clone(p)
            level.platforms.append(c)
            selected = c.id
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

    // a screen point back to unscaled canvas coords, for the palette drops
    private func toCanvas(_ p: CGPoint, _ w: CGFloat, _ h: CGFloat) -> CGPoint {
        CGPoint(x: (p.x - w / 2 - pan.width) / zoom + w / 2,
                y: (p.y - h / 2 - pan.height) / zoom + h / 2)
    }

    // keeps the zoomed canvas from panning past its own edges
    private func clampPan(_ p: CGSize, _ w: CGFloat, _ h: CGFloat) -> CGSize {
        let mx = w / 2 * (zoom - 1), my = h / 2 * (zoom - 1)
        return CGSize(width: min(max(p.width, -mx), mx), height: min(max(p.height, -my), my))
    }
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
    @State private var jetpackFuel: CGFloat = 1
    @State private var heldDirection: CGFloat = 0
    @State private var equippedSlots: [String?] = [nil, nil]
    @State private var showInventory = false
    @ObservedObject private var settings = GameSettings.shared

    init(level: LevelData, onExit: @escaping () -> Void) {
        self.level = level
        self.onExit = onExit
        // real screen size like the game, so the gate lands at the bar top
        let s = LevelScene(size: UIScreen.main.bounds.size)
        s.customLevel = level
        s.bottomInset = GameTabBar.height
        _scene = State(initialValue: s)
    }

    private var equippedPowers: Set<Powerup> { InventoryItem.powers(of: equippedSlots) }

    private func applyEquip() {
        let p = equippedPowers
        scene.extraJumps = p.contains(.doubleJump) ? 1 : 0
        scene.hasDash = p.contains(.dash)
        scene.hasJetpack = p.contains(.jetpack)
        scene.hasSpikeBoots = p.contains(.spikeBoots)
    }

    // composed exactly like the game feed so the gate and bar line up identically
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.gameBG
            GameSpriteView(scene: scene, renderScale: settings.renderScale, framerate: settings.framerate)
                .ignoresSafeArea()
            Button(action: onExit) {
                Image(systemName: "chevron.left").font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white).shadow(radius: 3).padding(24)
            }
            .padding(.top, 54)
        }
        .overlay {
            if showInventory {
                ZStack(alignment: .bottom) {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(Color.black.opacity(0.45))
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                                showInventory = false
                            }
                        }
                    InventoryPanel(owned: level.powerups, slots: $equippedSlots, free: true)
                        .padding(.bottom, GameTabBar.height)
                        .transition(.move(edge: .bottom))
                }
            }
        }
        .onChange(of: equippedSlots) { _ in applyEquip() }
        .overlay(alignment: .bottom) {
            GameTabBar(gateUnlocked: gateUnlocked,
                       dashEnabled: equippedPowers.contains(.dash), dashReady: dashReady,
                       wingsEnabled: equippedPowers.contains(.doubleJump),
                       jumpReady: jumpReady, airJumpReady: airJumpReady,
                       onMove: { scene.setMove($0) },
                       onJump: { scene.jump() },
                       onDash: { scene.dash() },
                       onJumpHold: { scene.setJumpHeld($0) },
                       jetpackEnabled: equippedPowers.contains(.jetpack),
                       jetpackFuel: jetpackFuel,
                       showInventory: $showInventory)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onAppear {
            scene.onHatchOpened = { gateUnlocked = true }
            scene.onJumpStateChanged = { jumpReady = $0; airJumpReady = $1 }
            scene.onDashStateChanged = { dashReady = $0 }
            scene.onJetpackFuel = { jetpackFuel = $0 }
            // beating the level just restarts it for testing
            scene.onFellThrough = { _ in
                gateUnlocked = false
                scene.reload()
            }
        }
    }
}
#endif
