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
            Color.black.ignoresSafeArea()

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
        .alert("Paste a level code", isPresented: $showImport) {
            TextField("code", text: $importText)
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

// small static drawing of a level, mirrors the save thumbnail idea
private struct LevelPreview: View {
    let level: LevelData

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ForEach(level.platforms) { p in
                Capsule().fill(.white)
                    .frame(width: p.isVertical ? 2 : CGFloat(p.w) * w,
                           height: p.isVertical ? CGFloat(p.w) * w : 2)
                    .position(x: CGFloat(p.x) * w, y: (1 - CGFloat(p.y)) * h)
            }
            Image(systemName: "heart.fill").font(.system(size: 8)).foregroundStyle(.white)
                .position(x: CGFloat(level.heartX) * w, y: (1 - CGFloat(level.heartY)) * h)
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
    @State private var playing = false
    @State private var heartPlaced: Bool
    @State private var draggingNewPlatform: UUID?
    @State private var draggingHeart = false

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
                Color.black

                // gate line and the empty heart slot, drawn exactly where the game puts them
                Rectangle().fill(.white.opacity(0.35)).frame(height: 1).position(x: w / 2, y: barY)
                Image(systemName: "heart").font(.system(size: 28)).foregroundStyle(.white.opacity(0.45))
                    .position(x: w - GameRef.slotRightInset, y: GameRef.slotTopOffset)

                Color.clear.contentShape(Rectangle()).onTapGesture { selected = nil }

                ForEach($level.platforms) { $p in platformView($p, w: w, h: h) }

                if heartPlaced || draggingHeart { heartView(w: w, h: h) }

                topBar
                paletteBar(w: w, h: h, barY: barY)
            }
            .coordinateSpace(name: "canvas")
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $playing) {
            LevelPlaytestView(level: level, onExit: { playing = false })
        }
    }

    private var topBar: some View {
        VStack {
            HStack(spacing: 14) {
                Button(action: exitSaving) {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                        .frame(width: 36, height: 36).glassEffect(.regular, in: Circle())
                }
                TextField("name", text: $level.name)
                    .font(.subheadline).bold().foregroundStyle(.white).frame(maxWidth: 150)
                Spacer()
                Button { playing = true } label: {
                    Image(systemName: "play.fill").font(.system(size: 16))
                        .frame(width: 36, height: 36).glassEffect(.regular, in: Circle())
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.top, 58)
            Spacer()
        }
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

                    Image(systemName: "heart.fill").font(.system(size: 26))
                        .foregroundStyle(heartPlaced ? Color(white: 0.35) : .white)
                        .frame(width: 64, height: 44).contentShape(Rectangle())
                        .allowsHitTesting(!heartPlaced)
                        .gesture(DragGesture(coordinateSpace: .named("canvas"))
                            .onChanged { v in
                                draggingHeart = true
                                level.heartX = fx(v.location.x, w)
                                level.heartY = fy(v.location.y, h)
                            }
                            .onEnded { _ in draggingHeart = false; heartPlaced = true; selected = nil })
                }
                .padding(.top, 16)
                Spacer()
            }
            .frame(height: GameRef.barHeight)
            .background(Color.black)
        }
    }

    // a draggable platform icon in the palette, horizontal or vertical
    private func platformPaletteItem(vertical: Bool, w: CGFloat, h: CGFloat) -> some View {
        Capsule().fill(.white)
            .frame(width: vertical ? 4 : 46, height: vertical ? 40 : 4)
            .frame(width: 56, height: 46).contentShape(Rectangle())
            .gesture(DragGesture(coordinateSpace: .named("canvas"))
                .onChanged { v in
                    if let id = draggingNewPlatform, let i = level.platforms.firstIndex(where: { $0.id == id }) {
                        level.platforms[i].x = fx(v.location.x, w)
                        level.platforms[i].y = fy(v.location.y, h)
                    } else {
                        let p = PlatformData(x: fx(v.location.x, w), y: fy(v.location.y, h),
                                             w: vertical ? 0.18 : 0.22, vertical: vertical ? true : nil)
                        level.platforms.append(p)
                        draggingNewPlatform = p.id
                        selected = p.id
                    }
                }
                .onEnded { _ in draggingNewPlatform = nil })
    }

    private func platformView(_ p: Binding<PlatformData>, w: CGFloat, h: CGFloat) -> some View {
        let isSel = selected == p.wrappedValue.id
        let cx = CGFloat(p.wrappedValue.x) * w
        let cy = (1 - CGFloat(p.wrappedValue.y)) * h
        let len = CGFloat(p.wrappedValue.w) * w
        let vert = p.wrappedValue.isVertical
        return ZStack {
            Capsule().fill(isSel ? Color.yellow : .white)
                .frame(width: vert ? 3 : len, height: vert ? len : 3)
            if isSel {
                Button { delete(p.wrappedValue.id) } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundStyle(.red)
                }
                .offset(x: vert ? 0 : -len / 2 - 16, y: vert ? -len / 2 - 16 : 0)
                Circle().fill(.yellow).frame(width: 16, height: 16)
                    .offset(x: vert ? 0 : len / 2 + 10, y: vert ? len / 2 + 10 : 0)
                    .gesture(DragGesture(coordinateSpace: .named("canvas")).onChanged { v in
                        let half = vert ? max(16, v.location.y - cy) : max(16, v.location.x - cx)
                        p.wrappedValue.w = clamp(Double(2 * half / w), 0.05, 0.9)
                    })
            }
        }
        .frame(width: vert ? 30 : max(len, 44), height: vert ? max(len, 44) : 30)
        .contentShape(Rectangle())
        .position(x: cx, y: cy)
        .gesture(DragGesture(coordinateSpace: .named("canvas")).onChanged { v in
            selected = p.wrappedValue.id
            p.wrappedValue.x = fx(v.location.x, w)
            p.wrappedValue.y = fy(v.location.y, h)
        })
        .onTapGesture { selected = p.wrappedValue.id }
    }

    private func heartView(w: CGFloat, h: CGFloat) -> some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 28)).foregroundStyle(.white)
            .shadow(color: .black.opacity(0.6), radius: 3)
            .position(x: CGFloat(level.heartX) * w, y: (1 - CGFloat(level.heartY)) * h)
            .gesture(DragGesture(coordinateSpace: .named("canvas")).onChanged { v in
                level.heartX = fx(v.location.x, w)
                level.heartY = fy(v.location.y, h)
            })
    }

    private func delete(_ id: UUID) {
        level.platforms.removeAll { $0.id == id }
        selected = nil
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
    @State private var heldDirection: CGFloat = 0

    init(level: LevelData, onExit: @escaping () -> Void) {
        self.level = level
        self.onExit = onExit
        // real screen size like the game, so the gate lands at the bar top
        let s = LevelScene(size: UIScreen.main.bounds.size)
        s.customLevel = level
        s.bottomInset = GameTabBar.height
        _scene = State(initialValue: s)
    }

    // composed exactly like the game feed so the gate and bar line up identically
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
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
                       dashEnabled: false, dashReady: true,
                       wingsEnabled: false, jumpReady: jumpReady, airJumpReady: airJumpReady,
                       onMove: { scene.setMove($0) },
                       onJump: { scene.jump() },
                       onDash: {})
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onAppear {
            scene.onHatchOpened = { gateUnlocked = true }
            scene.onJumpStateChanged = { jumpReady = $0; airJumpReady = $1 }
            // beating the level just restarts it for testing
            scene.onFellThrough = { _ in
                gateUnlocked = false
                scene.reload()
            }
        }
    }
}
#endif
