import Foundation
import simd

/// Minimal fiber-based task/job system for parallel work
@MainActor
class TaskJobSystem {

    // MARK: - Types

    typealias JobID = UUID

    struct Job {
        let id: JobID
        let name: String
        let priority: Priority
        let work: @Sendable () async -> Void
        var dependencies: [JobID] = []
    }

    enum Priority: Int, Comparable {
        case low = 0
        case normal = 1
        case high = 2
        case critical = 3

        static func < (lhs: Priority, rhs: Priority) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }

    // MARK: - Job Queue

    private var jobs: [JobID: Job] = [:]
    private var pendingJobs: [JobID] = []
    private var runningJobs: Set<JobID> = []
    private var completedJobs: Set<JobID> = []

    // MARK: - Worker Configuration

    private let maxConcurrentJobs: Int
    private var isRunning = false

    // MARK: - Statistics

    private(set) var jobsScheduled: Int = 0
    private(set) var jobsCompleted: Int = 0
    private(set) var jobsFailed: Int = 0
    private var jobExecutionTimes: [TimeInterval] = []

    // MARK: - Initialization

    init(maxConcurrentJobs: Int = 4) {
        self.maxConcurrentJobs = maxConcurrentJobs
        print("✅ Task/Job System initialized (max concurrent: \(maxConcurrentJobs))")
    }

    // MARK: - Job Scheduling

    /// Schedule a job for execution
    func schedule(
        name: String,
        priority: Priority = .normal,
        dependencies: [JobID] = [],
        work: @Sendable @escaping () async -> Void
    ) -> JobID {
        let id = UUID()

        let job = Job(
            id: id,
            name: name,
            priority: priority,
            work: work,
            dependencies: dependencies
        )

        jobs[id] = job
        pendingJobs.append(id)
        jobsScheduled += 1

        // Sort by priority
        pendingJobs.sort { id1, id2 in
            let job1 = jobs[id1]!
            let job2 = jobs[id2]!
            return job1.priority > job2.priority
        }

        return id
    }

    /// Execute all pending jobs
    func execute() async {
        guard !isRunning else { return }
        isRunning = true

        while !pendingJobs.isEmpty {
            // Execute jobs that have no pending dependencies
            let readyJobs = pendingJobs.filter { jobID in
                guard let job = jobs[jobID] else { return false }
                return job.dependencies.allSatisfy { completedJobs.contains($0) }
            }

            // Limit concurrent execution
            let jobsToRun = Array(readyJobs.prefix(maxConcurrentJobs - runningJobs.count))

            if jobsToRun.isEmpty {
                // No jobs ready, wait briefly
                try? await Task.sleep(nanoseconds: 1_000_000)  // 1ms
                continue
            }

            // Execute jobs concurrently
            await withTaskGroup(of: JobID.self) { group in
                for jobID in jobsToRun {
                    guard let job = jobs[jobID] else { continue }

                    runningJobs.insert(jobID)
                    pendingJobs.removeAll { $0 == jobID }

                    group.addTask {
                        await self.executeJob(job)
                        return jobID
                    }
                }

                // Wait for all to complete
                for await completedID in group {
                    runningJobs.remove(completedID)
                    completedJobs.insert(completedID)
                }
            }
        }

        isRunning = false
    }

    private func executeJob(_ job: Job) async {
        let startTime = CACurrentMediaTime()

        do {
            await job.work()
            jobsCompleted += 1
        } catch {
            print("Job '\(job.name)' failed: \(error)")
            jobsFailed += 1
        }

        let executionTime = CACurrentMediaTime() - startTime
        jobExecutionTimes.append(executionTime)

        if jobExecutionTimes.count > 100 {
            jobExecutionTimes.removeFirst()
        }
    }

    // MARK: - Parallel ECS Systems

    /// Execute multiple ECS systems in parallel
    func executeECSSystems(_ systems: [@Sendable () async -> Void]) async {
        var jobIDs: [JobID] = []

        for (index, system) in systems.enumerated() {
            let id = schedule(name: "ECS System \(index)", priority: .normal, work: system)
            jobIDs.append(id)
        }

        await execute()
    }

    // MARK: - Background Tasks

    /// Schedule background task (low priority, non-blocking)
    func scheduleBackground(
        name: String,
        work: @Sendable @escaping () async -> Void
    ) -> JobID {
        return schedule(name: name, priority: .low, work: work)
    }

    /// Schedule critical task (high priority)
    func scheduleCritical(
        name: String,
        work: @Sendable @escaping () async -> Void
    ) -> JobID {
        return schedule(name: name, priority: .critical, work: work)
    }

    // MARK: - Control

    /// Wait for specific job to complete
    func waitFor(job jobID: JobID) async {
        while !completedJobs.contains(jobID) {
            try? await Task.sleep(nanoseconds: 1_000_000)  // 1ms
        }
    }

    /// Wait for all jobs to complete
    func waitForAll() async {
        while !pendingJobs.isEmpty || !runningJobs.isEmpty {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    /// Clear completed jobs
    func clearCompleted() {
        for jobID in completedJobs {
            jobs.removeValue(forKey: jobID)
        }
        completedJobs.removeAll()
    }

    /// Cancel all pending jobs
    func cancelAll() {
        pendingJobs.removeAll()
        jobs.removeAll()
        print("All jobs cancelled")
    }

    // MARK: - Statistics

    func getJobStats() -> JobStats {
        let avgExecutionTime = jobExecutionTimes.isEmpty
            ? 0
            : jobExecutionTimes.reduce(0, +) / Double(jobExecutionTimes.count)

        return JobStats(
            jobsScheduled: jobsScheduled,
            jobsCompleted: jobsCompleted,
            jobsFailed: jobsFailed,
            pendingCount: pendingJobs.count,
            runningCount: runningJobs.count,
            averageExecutionTime: avgExecutionTime,
            maxConcurrent: maxConcurrentJobs
        )
    }

    func getDebugInfo() -> String {
        let stats = getJobStats()

        var info = "=== Task/Job System ===\n"
        info += "Scheduled: \(stats.jobsScheduled)\n"
        info += "Completed: \(stats.jobsCompleted)\n"
        info += "Failed: \(stats.jobsFailed)\n"
        info += "Pending: \(stats.pendingCount)\n"
        info += "Running: \(stats.runningCount)\n"
        info += "Avg Time: \(String(format: "%.2f", stats.averageExecutionTime * 1000))ms\n"
        info += "Max Concurrent: \(stats.maxConcurrent)\n"
        info += "====================="

        return info
    }
}

struct JobStats {
    let jobsScheduled: Int
    let jobsCompleted: Int
    let jobsFailed: Int
    let pendingCount: Int
    let runningCount: Int
    let averageExecutionTime: TimeInterval
    let maxConcurrent: Int
}
