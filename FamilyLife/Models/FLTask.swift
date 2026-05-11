import Foundation
import SwiftData

@Model
final class FLTask {
    var serverId: Int?
    var category: String
    var title: String
    var taskDescription: String?
    var status: String
    var priority: String
    var dueDate: String?
    var dueTime: String?
    var assignedTo: String?
    var createdBy: String
    var recurrencePattern: String?
    var tags: String?
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?

    init(
        serverId: Int? = nil,
        category: String,
        title: String,
        taskDescription: String? = nil,
        status: String = "active",
        priority: String = "medium",
        dueDate: String? = nil,
        dueTime: String? = nil,
        assignedTo: String? = nil,
        createdBy: String = "jesse",
        recurrencePattern: String? = nil,
        tags: String? = nil
    ) {
        self.serverId = serverId
        self.category = category
        self.title = title
        self.taskDescription = taskDescription
        self.status = status
        self.priority = priority
        self.dueDate = dueDate
        self.dueTime = dueTime
        self.assignedTo = assignedTo
        self.createdBy = createdBy
        self.recurrencePattern = recurrencePattern
        self.tags = tags
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// Codable struct for API responses
struct TaskResponse: Codable, Identifiable {
    let id: Int
    let category: String
    let title: String
    let description: String?
    let status: String
    let priority: String
    let due_date: String?
    let due_time: String?
    let assigned_to: String?
    let created_by: String?
    let recurrence_pattern: String?
    let tags: String?
    let created_at: String?
    let updated_at: String?
    let completed_at: String?
}
