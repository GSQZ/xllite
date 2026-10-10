import Foundation

@main
enum CourseReminderScheduleTest {
  static func main() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func raw(_ start: Date, id: String = "course-1") -> [String: Any] {
      ["id": id, "title": "数学", "location": "教学楼101", "teacher": "老师",
       "showAt": start.addingTimeInterval(-900).timeIntervalSince1970 * 1000,
       "startsAt": start.timeIntervalSince1970 * 1000,
       "endsAt": start.addingTimeInterval(6000).timeIntervalSince1970 * 1000,
       "dismissAt": start.addingTimeInterval(60).timeIntervalSince1970 * 1000]
    }
    let course = NativeCourseReminder(json: raw(now.addingTimeInterval(3600)))!
    precondition(course.startsAt.timeIntervalSince(course.showAt) == 900)
    precondition(course.dismissAt.timeIntervalSince(course.startsAt) == 60)
    precondition(course.identifier(scope: "a") == course.identifier(scope: "a"))
    precondition(course.identifier(scope: "a") != course.identifier(scope: "b"))
    precondition(!course.identifier(scope: "private-account").contains("private-account"))
    var malformed = raw(now)
    malformed["showAt"] = true
    precondition(NativeCourseReminder(json: malformed) == nil)
    malformed = raw(now)
    malformed["dismissAt"] = Double.infinity
    precondition(NativeCourseReminder(json: malformed) == nil)
    malformed = raw(now)
    malformed["endsAt"] = now.addingTimeInterval(-1).timeIntervalSince1970 * 1000
    precondition(NativeCourseReminder(json: malformed) == nil)
    malformed = raw(now)
    malformed["showAt"] = now.timeIntervalSince1970 * 1000
    precondition(NativeCourseReminder(json: malformed) == nil)
    let expired = NativeCourseReminder(json: raw(now.addingTimeInterval(-60), id: "expired"))!
    let distant = NativeCourseReminder(json: raw(now.addingTimeInterval(8 * 86400), id: "distant"))!
    let upcoming = NativeCourseReminder.upcoming([course, course, expired, distant], now: now)
    precondition(upcoming == [course])
    let many = (0..<80).map {
      NativeCourseReminder(json: raw(now.addingTimeInterval(Double($0 + 1) * 1000), id: "\($0)"))!
    }
    precondition(NativeCourseReminder.upcoming(Array(many.reversed()), now: now).count == 48)
    let saved = try JSONEncoder().encode([course])
    let restored = try JSONDecoder().decode([NativeCourseReminder].self, from: saved)
    precondition(restored == [course])
    print("Native course reminder schedule: all assertions passed")
  }
}
