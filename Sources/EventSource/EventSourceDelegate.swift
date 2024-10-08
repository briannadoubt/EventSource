//
//  EventSourceDelegate.swift
//  PocketBase
//
//  Created by Brianna Zamora on 9/1/24.
//

import Foundation
import os

final class EventSourceDelegate: NSObject, URLSessionDataDelegate {
    static var logger: Logger {
        Logger(
            subsystem: "EventSource",
            category: "EventSourceDelegate"
        )
    }
    
    let eventSource: EventSource
    
    init(eventSource: EventSource) {
        self.eventSource = eventSource
    }
    
    // MARK: URLSession Delegates

    // Tells the delegate that the task finished transferring data.
    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        Task {
            await endSession(error: error)
        }
    }
    
    func endSession(error: Error? = nil) async {
        await eventSource.utf8LineParser.closeAndReset()
        let currentRetry = await eventSource.eventParser.reset()
        
        guard await eventSource.readyState != .shutdown else { return }
        
        if let error = error {
            if (error as NSError).code != NSURLErrorCancelled {
                Self.logger.error("Connection error: \(error)")
                if await eventSource.dispatchError(error: error) == .shutdown {
                    Self.logger.warning("Connection has been explicitly shut down by error handler")
                    if await eventSource.readyState == .open {
                        await eventSource.config.handler.onClosed()
                    }
                    await eventSource.set(readyState: .shutdown)
                    return
                }
            }
        } else {
            Self.logger.warning("Connection unexpectedly closed.")
        }
        
        if await eventSource.readyState == .open {
            await eventSource.config.handler.onClosed()
        }
        
        await eventSource.set(readyState: .closed)
        let sleep = await eventSource.reconnectionTimer.reconnectDelay(baseDelay: currentRetry)
        // this formatting shenanigans is to workaround String not implementing CVarArg on Swift<5.4 on Linux
        Self.logger.log("Waiting \(String(format: "%.3f", sleep)) seconds before reconnecting...")
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, macCatalyst 16.0, *) {
            try? await Task.sleep(for: .seconds(sleep))
        } else {
            try? await Task.sleep(nanoseconds: UInt64(sleep) * 1_000_000_000)
        }
        await eventSource.connect()
    }
    
    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse
    ) async -> URLSession.ResponseDisposition {
        await handleInitialReply(response: response)
    }
    
    func handleInitialReply(response: URLResponse) async -> URLSession.ResponseDisposition {
        Self.logger.debug("Initial reply received")
        // swiftlint:disable:next force_cast
        let httpResponse = response as? HTTPURLResponse
        let statusCode = httpResponse?.statusCode ?? 500
        if (200..<300).contains(statusCode) && statusCode != 204 {
            await eventSource.reconnectionTimer.set(connectedTime: Date())
            await eventSource.set(readyState: .open)
            await eventSource.config.handler.onOpened()
            return .allow
        } else {
            Self.logger.info("Unsuccessful response: \(String(format: "%d", statusCode))")
            let statusCode = statusCode
            let dispatchError = await eventSource.dispatchError(error: UnsuccessfulResponseError(responseCode: statusCode))
            if dispatchError == .shutdown {
                Self.logger.info("Connection has been explicitly shut down by error handler")
                await eventSource.set(readyState: .shutdown)
            }
            return .cancel
        }
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        Task {
            await handle(data: data)
        }
    }
    
    func handle(data: Data) async {
        for line in await eventSource.utf8LineParser.append(data) {
            await eventSource.eventParser.parse(line: line)
        }
    }
}
