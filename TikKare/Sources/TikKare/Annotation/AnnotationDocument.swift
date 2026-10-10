import AppKit

/// A captured image plus its annotations and undo history.
@MainActor
final class AnnotationDocument {
    let baseImage: CGImage
    /// Pixels per point of `baseImage`.
    let scale: CGFloat

    private(set) var annotations: [Annotation] = []
    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []
    private var pixelatedCache: CGImage?

    private var observers: [UUID: () -> Void] = [:]

    init(baseImage: CGImage, scale: CGFloat) {
        self.baseImage = baseImage
        self.scale = max(scale, 1)
    }

    var pointSize: CGSize {
        CGSize(width: CGFloat(baseImage.width) / scale, height: CGFloat(baseImage.height) / scale)
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var isEmpty: Bool { annotations.isEmpty }

    var nextNumber: Int {
        let used: [Int] = annotations.compactMap {
            if case .number(let n, _) = $0.kind { return n }
            return nil
        }
        return (used.max() ?? 0) + 1
    }

    var pixelatedImage: CGImage? {
        if pixelatedCache == nil { pixelatedCache = Pixelator.pixelate(baseImage, blockSize: 12 * scale) }
        return pixelatedCache
    }

    /// Saves the current state so the next mutation can be undone.
    func checkpoint() {
        undoStack.append(annotations)
        redoStack.removeAll()
    }

    func add(_ annotation: Annotation) {
        checkpoint()
        annotations.append(annotation)
        notify()
    }

    /// Mutates an annotation without creating an undo step (used while dragging).
    func update(_ annotation: Annotation) {
        guard let index = annotations.firstIndex(where: { $0.id == annotation.id }) else { return }
        annotations[index] = annotation
        notify()
    }

    func remove(id: UUID, recordUndo: Bool) {
        if recordUndo { checkpoint() }
        annotations.removeAll { $0.id == id }
        notify()
    }

    @discardableResult
    func observe(_ handler: @escaping () -> Void) -> UUID {
        let id: UUID = UUID()
        observers[id] = handler
        return id
    }

    func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
    }

    private func notify() {
        for handler in observers.values { handler() }
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
        notify()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
        notify()
    }
}
