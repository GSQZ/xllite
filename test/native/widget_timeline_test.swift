import Foundation

// Run with: xcrun swiftc ios/Runner/WidgetSnapshotStore.swift
// test/native/widget_timeline_test.swift -o /tmp/xinli-widget-test && /tmp/xinli-widget-test
@main
enum WidgetTimelineTest {
  static func main() throws {
    let payload = #"""
    {"v":2,"expiresAt":9000000,"entries":[
      {"at":0,"status":"upcoming","title":"数学","subtitle":"教室","timeRange":"10:00 - 10:45","week":6,"accent":4280127448,"startsAt":600000,"endsAt":3300000},
      {"at":600000,"status":"in_class","title":"数学","subtitle":"教室","timeRange":"10:00 - 10:45","week":6,"accent":4280127448,"startsAt":600000,"endsAt":3300000},
      {"at":3300000,"status":"done","title":"","subtitle":"","timeRange":"","week":6,"accent":4280127448},
      {"at":8000000,"status":"free","title":"","subtitle":"","timeRange":"","week":6,"accent":4280127448}
    ]}
    """#
    let timeline = try JSONDecoder().decode(WidgetTimeline.self, from: Data(payload.utf8))
    func state(_ seconds: Double) -> WidgetSnapshot? { timeline.snapshot(at: Date(timeIntervalSince1970: seconds)) }
    precondition(state(-1) == nil)
    precondition(state(300)?.minutes == 5)
    precondition(state(600)?.status == .inClass)
    precondition(state(1950)?.progress == 0.5)
    precondition(state(1950)?.minutes == 22)
    precondition(state(3300)?.status == .done)
    precondition(state(7999)?.title == "")
    precondition(state(8000)?.status == .free)
    precondition(state(9000) == nil)
    print("Native Swift timeline: all assertions passed")
  }
}
