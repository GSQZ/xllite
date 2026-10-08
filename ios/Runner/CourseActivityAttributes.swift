import ActivityKit
import Foundation

@available(iOS 16.1, *)
struct CourseActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var accent: Int
  }

  var occurrenceID: String
  var title: String
  var location: String
  var teacher: String
  var showAt: Date
  var startsAt: Date
  var dismissAt: Date
  var isTest: Bool
}
