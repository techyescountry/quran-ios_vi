//
//  Task+Extension.swift
//
//
//  Created by Mohamed Afifi on 2023-05-02.
//

import AsyncAlgorithms
import Foundation

public final class CancellableTask: Hashable {
    private let cancel: () -> Void

    init(task: Task<some Any, some Any>) {
        cancel = { task.cancel() }
    }

    deinit {
        cancel()
    }

    public static func == (lhs: CancellableTask, rhs: CancellableTask) -> Bool {
        lhs === rhs
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

extension Task {
    public func asCancellableTask() -> CancellableTask {
        CancellableTask(task: self)
    }
}

extension AsyncChannel {
    public func next() async -> Element? {
        var iterator = makeAsyncIterator()
        return await iterator.next()
    }
}

extension AsyncSequence {
    public func collect() async rethrows -> [Element] {
        try await reduce(into: [Element]()) { $0.append($1) }
    }
}
