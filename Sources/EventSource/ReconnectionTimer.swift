//
//  ReconnectionTimer.swift
//  PocketBase
//
//  Created by Brianna Zamora on 9/1/24.
//

import Foundation

actor ReconnectionTimer {
    private let maxDelay: TimeInterval
    private let resetInterval: TimeInterval

    var backoffCount: Int = 0
    var connectedTime: Date?
    func set(connectedTime: Date?) {
        self.connectedTime = connectedTime
    }

    init(maxDelay: TimeInterval, resetInterval: TimeInterval) {
        self.maxDelay = maxDelay
        self.resetInterval = resetInterval
    }

    func reconnectDelay(baseDelay: TimeInterval) -> TimeInterval {
        backoffCount += 1
        if let connectedTime = connectedTime, Date().timeIntervalSince(connectedTime) >= resetInterval {
            backoffCount = 0
        }
        self.connectedTime = nil
        let maxSleep = min(maxDelay, baseDelay * pow(2.0, Double(backoffCount)))
        return maxSleep / 2 + Double.random(in: 0...(maxSleep / 2))
    }
}
