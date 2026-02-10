import Foundation

public struct ExecutionLimits: Sendable {
    public var instructionBudget: Int
    public var maxCallDepth: Int
    public var maxValueStackDepth: Int
    public var wallClockLimit: Duration

    public init(
        instructionBudget: Int = 250_000,
        maxCallDepth: Int = 128,
        maxValueStackDepth: Int = 2_048,
        wallClockLimit: Duration = .seconds(1)
    ) {
        self.instructionBudget = instructionBudget
        self.maxCallDepth = maxCallDepth
        self.maxValueStackDepth = maxValueStackDepth
        self.wallClockLimit = wallClockLimit
    }
}

public final class ResourceGuard: @unchecked Sendable {
    private let limits: ExecutionLimits
    private let startTime: ContinuousClock.Instant
    private var executedInstructions: Int = 0
    private let clock = ContinuousClock()

    public init(limits: ExecutionLimits) {
        self.limits = limits
        self.startTime = clock.now
    }

    public func onInstructionExecuted() throws {
        executedInstructions += 1
        if executedInstructions > limits.instructionBudget {
            throw ResourceError.instructionBudgetExceeded(limit: limits.instructionBudget)
        }
        if clock.now - startTime > limits.wallClockLimit {
            throw ResourceError.timeLimitExceeded(limit: limits.wallClockLimit)
        }
    }

    public func ensureCallDepth(_ depth: Int) throws {
        if depth > limits.maxCallDepth {
            throw ResourceError.callDepthExceeded(limit: limits.maxCallDepth)
        }
    }

    public func ensureValueStackDepth(_ depth: Int) throws {
        if depth > limits.maxValueStackDepth {
            throw ResourceError.valueStackExceeded(limit: limits.maxValueStackDepth)
        }
    }
}

public enum ResourceError: Error, Sendable, Equatable {
    case instructionBudgetExceeded(limit: Int)
    case callDepthExceeded(limit: Int)
    case valueStackExceeded(limit: Int)
    case timeLimitExceeded(limit: Duration)
}
