import Testing
@testable import TPCore

extension TPCoreTestsRoot {

@Suite struct HomeWebSocketClientTests {
    @Test func decodesDeviceOnline() {
        let event = HomeWebSocketClient.decode(#"{"event": "device_online", "data": {"id": "blind-1"}}"#)
        #expect(event == .deviceOnline(id: "blind-1"))
    }

    @Test func decodesDeviceOffline() {
        let event = HomeWebSocketClient.decode(#"{"event": "device_offline", "data": {"id": "blind-1"}}"#)
        #expect(event == .deviceOffline(id: "blind-1"))
    }

    @Test func decodesDeviceState() {
        let event = HomeWebSocketClient.decode(#"""
        {"event": "device_state", "data": {"id": "blind-1", "state": {"position": 42, "motor_state": 2}}}
        """#)
        #expect(event == .deviceState(id: "blind-1", position: 42, motorState: 2))
    }

    @Test func returnsNilForUnknownEvent() {
        let event = HomeWebSocketClient.decode(#"{"event": "discovery_complete", "data": {}}"#)
        #expect(event == nil)
    }

    @Test func returnsNilForMalformedJSON() {
        let event = HomeWebSocketClient.decode("not json")
        #expect(event == nil)
    }
}

}
