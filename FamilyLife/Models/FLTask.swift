import Foundation

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
