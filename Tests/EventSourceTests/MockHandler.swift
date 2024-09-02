//
//  MockHandler.swift
//  EventSource
//
//  Created by Brianna Zamora on 9/1/24.
//

import Foundation
@testable import EventSource

enum ReceivedEvent: Equatable, Sendable {
    case opened, closed, message(String, MessageEvent), comment(String), error(Error)

    static func == (lhs: ReceivedEvent, rhs: ReceivedEvent) -> Bool {
        switch (lhs, rhs) {
        case (.opened, .opened):
            return true
        case (.closed, .closed):
            return true
        case let (.message(typeLhs, eventLhs), .message(typeRhs, eventRhs)):
            return typeLhs == typeRhs && eventLhs == eventRhs
        case let (.comment(lhs), .comment(rhs)):
            return lhs == rhs
        case (.error, .error):
            return true
        default:
            return false
        }
    }
}

actor MockHandler: EventHandler, Sendable {
    var events = EventSink<ReceivedEvent>()
    
    func expectEvent(maxWait: TimeInterval = 1.0) -> ReceivedEvent? {
        events.expectEvent(maxWait: maxWait)
    }
    
    func maybeEvent() -> ReceivedEvent? {
        events.maybeEvent()
    }

    func expectNoEvent(within: TimeInterval = 0.1) {
        events.expectNoEvent(within: within)
    }
    
    func onOpened() async {
        events.record(.opened)
    }
    
    func onClosed() async {
        events.record(.closed)
    }
    
    func onMessage(eventType: String, messageEvent: MessageEvent) async {
        events.record(.message(eventType, messageEvent))
    }
    
    func onComment(comment: String) async {
        events.record(.comment(comment))
    }
    
    func onError(error: Error) async {
        events.record(.error(error))
    }
}
