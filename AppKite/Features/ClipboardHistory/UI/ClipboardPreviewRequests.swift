import Foundation
import Observation

@MainActor
@Observable
final class ClipboardPreviewRequests {
    enum Result {
        case summary
        case ready(ClipboardPreview)
    }

    private struct Request {
        let entry: ClipboardEntry
        let store: any ClipboardHistoryStore
    }

    private(set) var results: [UUID: Result] = [:]
    @ObservationIgnored private let render: RenderClipboardPreview
    @ObservationIgnored private var visible: [UUID: Request] = [:]
    @ObservationIgnored private var waiting: [UUID] = []
    @ObservationIgnored private var jobs: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var cacheOrder: [UUID] = []
    @ObservationIgnored private var cacheBytes = 0

    init(render: @escaping RenderClipboardPreview) {
        self.render = render
    }

    isolated deinit {
        for job in jobs.values { job.cancel() }
    }

    static func needsPreview(_ entry: ClipboardEntry) -> Bool {
        switch entry.kind {
        case .image, .pdf, .files, .spreadsheet, .mixed: true
        default: false
        }
    }

    func show(_ entry: ClipboardEntry, store: any ClipboardHistoryStore) {
        guard Self.needsPreview(entry), visible[entry.id] == nil else { return }
        visible[entry.id] = Request(entry: entry, store: store)
        if results[entry.id] != nil {
            cacheOrder.removeAll { $0 == entry.id }
            cacheOrder.append(entry.id)
        } else if jobs[entry.id] == nil {
            waiting.append(entry.id)
        }
        startJobs()
    }

    func hide(_ id: UUID) {
        visible.removeValue(forKey: id)
        waiting.removeAll { $0 == id }
        jobs[id]?.cancel()
    }

    func remove(_ id: UUID) {
        hide(id)
        if let result = results.removeValue(forKey: id) { cacheBytes -= cost(of: result) }
        cacheOrder.removeAll { $0 == id }
    }

    func reset() {
        visible.removeAll()
        waiting.removeAll()
        for job in jobs.values { job.cancel() }
        results.removeAll()
        cacheOrder.removeAll()
        cacheBytes = 0
    }

    private func startJobs() {
        while jobs.count < 2, !waiting.isEmpty {
            let id = waiting.removeFirst()
            guard let request = visible[id], jobs[id] == nil, results[id] == nil else { continue }

            jobs[id] = Task { [weak self, render] in
                let result = await Self.load(request, render: render)
                guard let self else { return }
                self.jobs.removeValue(forKey: id)
                if self.visible[id] != nil {
                    if Task.isCancelled {
                        self.waiting.append(id)
                    } else {
                        self.keep(result, for: id)
                    }
                }
                self.startJobs()
            }
        }
    }

    private static func load(_ request: Request, render: @escaping RenderClipboardPreview) async
        -> Result
    {
        do {
            guard let source = try await request.store.previewSource(for: request.entry.id) else {
                return .summary
            }
            try Task.checkCancellation()
            let rendering = Task.detached(priority: .utility) { await render(source) }
            let preview = await withTaskCancellationHandler {
                await rendering.value
            } onCancel: {
                rendering.cancel()
            }
            return preview.map(Result.ready) ?? .summary
        } catch is CancellationError {
            return .summary
        } catch {
            let entry = request.entry
            let kind: ClipboardPreview.Kind =
                switch entry.kind {
                case .image: .image
                case .pdf: .document
                case .spreadsheet: .table
                default: .selection
                }
            return .ready(.init(kind: kind, content: .unavailable, name: entry.text))
        }
    }

    private func keep(_ result: Result, for id: UUID) {
        results[id] = result
        cacheOrder.append(id)
        cacheBytes += cost(of: result)
        while cacheOrder.count > 48 || cacheBytes > 24 * 1_024 * 1_024 {
            guard let index = cacheOrder.firstIndex(where: { visible[$0] == nil }) else {
                // The renderer bounds each individual preview and only visible cards remain here.
                break
            }
            let oldest = cacheOrder.remove(at: index)
            if let result = results.removeValue(forKey: oldest) { cacheBytes -= cost(of: result) }
        }
    }

    #if DEBUG
        func seed(_ preview: ClipboardPreview, for id: UUID) {
            keep(.ready(preview), for: id)
        }
    #endif

    private func cost(of result: Result) -> Int {
        guard case .ready(let preview) = result else { return 0 }
        switch preview.content {
        case .picture(let picture): return picture.png.count
        case .mosaic(let tiles, _): return tiles.reduce(0) { $0 + ($1.picture?.png.count ?? 0) }
        default: return 0
        }
    }
}
