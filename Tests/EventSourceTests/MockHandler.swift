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
    var events: [ReceivedEvent] = []
    
    func onOpened() async {
        events.append(.opened)
    }
    
    func onClosed() async {
        events.append(.closed)
    }
    
    func onMessage(eventType: String, messageEvent: MessageEvent) async {
        events.append(.message(eventType, messageEvent))
    }
    
    func onComment(comment: String) async {
        events.append(.comment(comment))
    }
    
    func onError(error: Error) async {
        events.append(.error(error))
    }
}
