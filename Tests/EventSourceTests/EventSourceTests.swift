//
//  EventSourceTests.swift
//  EventSource
//
//  Created by Brianna Zamora on 9/1/24.
//

import Testing
@testable import EventSource
import ConcurrencyExtras

#if os(Linux) || os(Windows)
import FoundationNetworking
#else
import Foundation
#endif

private enum TestError: Error {
    case fake
    init() {
        self = .fake
    }
}

extension EventSource {
    func connectForTests(statusCode: Int = 200) async {
        if let delegate {
            let response = HTTPURLResponse(
                url: URL(string: "http://example.com")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": "text/event-stream; charset=utf-8",
                    "Transfer-Encoding": "chunked"
                ]
            )!
            if statusCode == 200 {
                await #expect(delegate.handleInitialReply(response: response) == .allow)
            } else {
                await #expect(delegate.handleInitialReply(response: response) == .cancel)
            }
        }
    }
    
    func sendTest(event: String) async {
        if let delegate {
            await delegate.handle(data: Data(event.utf8))
        }
    }
    
    func endTestSession(with error: Error? = nil) async {
        await delegate?.endSession(error: error)
    }
}

@Suite
struct EventSourceTests {
    @Test
    func configDefaults() async {
        let url = URL(string: "abc")!
        let config = EventSource.Config(handler: MockHandler(), url: url)
        #expect(config.url == url)
        #expect(config.method == "GET")
        #expect(config.body == nil)
        #expect(config.lastEventId == "")
        #expect(config.headers == [:])
        #expect(config.reconnectTime == 1.0)
        #expect(config.maxReconnectTime == 30.0)
        #expect(config.backoffResetThreshold == 60.0)
        #expect(config.idleTimeout == 300.0)
        #expect(config.headerTransform(["abc": "123"]) == ["abc": "123"])
        await #expect(config.connectionErrorHandler(TestError()) == .proceed)
        UserDefaults.eventSource.removeObject(forKey: "com.briannadoubt.event-source.last-event-id")
        UserDefaults.eventSource.synchronize()
    }

    @Test
    func configModification() async {
        let mockHandler = MockHandler()
        
        let url = URL(string: "abc")!
        var config = EventSource.Config(handler: mockHandler, url: url)

        let testBody = "test data".data(using: .utf8)
        let testHeaders = ["Authorization": "basic abc"]

        config.method = "REPORT"
        config.body = testBody
        config.lastEventId = "eventId"
        config.headers = testHeaders
        config.reconnectTime = 2.0
        config.maxReconnectTime = 60.0
        config.backoffResetThreshold = 120.0
        config.idleTimeout = 180.0
        config.headerTransform = { _ in [:] }
        config.connectionErrorHandler = { _ in .shutdown }

        #expect(config.url == url)
        #expect(config.method == "REPORT")
        #expect(config.body == testBody)
        #expect(config.lastEventId == "eventId")
        #expect(config.headers == testHeaders)
        #expect(config.headerTransform(config.headers) == [:])
        #expect(config.reconnectTime == 2.0)
        #expect(config.maxReconnectTime == 60.0)
        #expect(config.backoffResetThreshold == 120.0)
        #expect(config.idleTimeout == 180.0)
        await #expect(config.connectionErrorHandler(TestError()) == .shutdown)
        UserDefaults.eventSource.removeObject(forKey: "com.briannadoubt.event-source.last-event-id")
        UserDefaults.eventSource.synchronize()
    }

    @Test
    func configUrlSession() {
        var config = EventSource.Config(handler: MockHandler(), url: URL(string: "abc")!)
        let defaultSessionConfig = config.urlSessionConfiguration
        #expect(defaultSessionConfig.timeoutIntervalForRequest == 300.0)
        #expect(defaultSessionConfig.httpAdditionalHeaders?["Accept"] as? String == "text/event-stream")
        #expect(defaultSessionConfig.httpAdditionalHeaders?["Cache-Control"] as? String == "no-cache")
        // Configuration should return a fresh session configuration each retrieval
        #expect(defaultSessionConfig !== config.urlSessionConfiguration)
        // Updating idleTimeout should effect session config
        config.idleTimeout = 600.0
        #expect(config.urlSessionConfiguration.timeoutIntervalForRequest == 600.0)
        #expect(defaultSessionConfig.timeoutIntervalForRequest == 300.0)
        // Updating returned urlSessionConfiguration without setting should not update the Config until set
        let sessionConfig = config.urlSessionConfiguration
        sessionConfig.allowsCellularAccess = false
        #expect(config.urlSessionConfiguration.allowsCellularAccess)
        config.urlSessionConfiguration = sessionConfig
        #expect(config.urlSessionConfiguration.allowsCellularAccess == false)
        #expect(sessionConfig !== config.urlSessionConfiguration)
        UserDefaults.eventSource.removeObject(forKey: "com.briannadoubt.event-source.last-event-id")
        UserDefaults.eventSource.synchronize()
    }

    @Test
    func lastEventIdFromConfig() async {
        let mockHandler = MockHandler()
        var config = EventSource.Config(handler: mockHandler, url: URL(string: "abc")!)
        var es = EventSource(config: config, sessionType: MockDataTaskSession.self)
        await #expect(es.getLastEventId() == "")
        config.lastEventId = "def"
        es = EventSource(config: config, sessionType: MockDataTaskSession.self)
        await #expect(es.getLastEventId() == "def")
        UserDefaults.eventSource.removeObject(forKey: "com.briannadoubt.event-source.last-event-id")
        UserDefaults.eventSource.synchronize()
    }
    
    @Test
    func createdSession() async {
        let mockHandler = MockHandler()
        let config = EventSource.Config(handler: mockHandler, url: URL(string: "abc")!)
        let configuration = config.urlSessionConfiguration
        #expect(configuration.timeoutIntervalForRequest == config.idleTimeout)
        #expect(configuration.httpAdditionalHeaders?["Accept"] as? String == "text/event-stream")
        #expect(configuration.httpAdditionalHeaders?["Cache-Control"] as? String == "no-cache")
        UserDefaults.eventSource.removeObject(forKey: "com.briannadoubt.event-source.last-event-id")
        UserDefaults.eventSource.synchronize()
    }

    @Test
    func createRequest() async {
        let mockHandler = MockHandler()
        
        // 192.0.2.1 is assigned as TEST-NET-1 reserved usage.
        var config = EventSource.Config(handler: mockHandler, url: URL(string: "http://192.0.2.1")!)
        // Testing default configs
        var request = await EventSource(config: config, sessionType: MockDataTaskSession.self).createRequest()
        #expect(request.url == config.url)
        #expect(request.httpMethod == config.method)
        #expect(request.httpBody == config.body)
        #expect(request.timeoutInterval == config.idleTimeout)
        let staticHeaders = ["Accept": "text/event-stream", "Cache-Control": "no-cache"]
        #expect(request.allHTTPHeaderFields == config.headers.merging(staticHeaders) { $1 })
        // Testing customized configs
        let testBody = "test data".data(using: .utf8)
        let testHeaders = ["removing": "a", "updating": "b"]
        let overrideHeaders = ["updating": "c", "last-event-id": "eventId2"]
        config.method = "REPORT"
        config.body = testBody
        config.lastEventId = "eventId"
        config.headers = testHeaders
        config.idleTimeout = 180.0
        config.headerTransform = { provided in
            #expect(provided == ["removing": "a", "updating": "b", "Last-Event-Id": "eventId", "Accept": "text/event-stream", "Cache-Control": "no-cache"])
            return overrideHeaders
        }
        request = await EventSource(config: config, sessionType: MockDataTaskSession.self).createRequest()
        #expect(request.url == config.url)
        #expect(request.httpMethod == config.method)
        #expect(request.httpBody == config.body)
        #expect(request.timeoutInterval == config.idleTimeout)
        #expect(request.allHTTPHeaderFields == overrideHeaders.merging(staticHeaders) { $1 })
        UserDefaults.eventSource.removeObject(forKey: "com.briannadoubt.event-source.last-event-id")
        UserDefaults.eventSource.synchronize()
    }

//    @Test
//    func dispatchError() async {
//        let mockHandler = MockHandler()
//        
//        var config = EventSource<MockDataTaskSession>.Config(handler: mockHandler, url: URL(string: "abc")!)
//        
////        var connectionErrorHandlerCallCount = 0
//        config.connectionErrorHandler = { error in
////            connectionErrorHandlerCallCount += 1
//            return .proceed
//        }
//
//        let es = EventSource(config: config, urlSession: MockDataTaskSession.self)
//        await #expect(es.dispatchError(error: TestError()) == .proceed)
////        #expect(connectionErrorHandlerCallCount == 1)
//        guard
//            case .error(let err) = await mockHandler.expectEvent(),
//            err is TestError
//        else {
//            Issue.record("handler should receive error if EventSource is not shutting down")
//            return
//        }
//        await mockHandler.events.expectNoEvent()
//        await #expect(es.dispatchError(error: TestError()) == .shutdown)
////        #expect(connectionErrorHandlerCallCount == 2)
//    }

    #if !os(Linux) && !os(Windows)
    @Test
    func startDefaultRequest() async {
        let config = EventSource.Config(
            handler: MockHandler(),
            url: URL(string: "http://example.com")!
        )
        let es = EventSource(config: config, sessionType: MockDataTaskSession.self)
        await es.start()
        let session = await es.urlSession as? MockDataTaskSession
        #expect(session?.lastRequest?.url == config.url)
        #expect(session?.lastRequest?.httpMethod == config.method)
        #expect(session?.lastRequest?.httpBody == config.body)
        #expect(session?.lastRequest?.timeoutInterval == config.idleTimeout)
        #expect(session?.lastRequest?.allHTTPHeaderFields?["Accept"] == "text/event-stream")
        #expect(session?.lastRequest?.allHTTPHeaderFields?["Cache-Control"] == "no-cache")
        #expect(session?.lastRequest?.allHTTPHeaderFields?["Last-Event-Id"] == nil)
        await es.stop()
        UserDefaults.eventSource.removeObject(forKey: "com.briannadoubt.event-source.last-event-id")
        UserDefaults.eventSource.synchronize()
    }

    @Test
    func startRequestWithConfiguration() async {
        let mockHandler = MockHandler()
        
        var config = EventSource.Config(handler: mockHandler, url: URL(string: "http://example.com")!)
        config.method = "REPORT"
        config.body = Data("test body".utf8)
        config.idleTimeout = 500.0
        config.lastEventId = "abc"
        config.headers = ["X-LD-Header": "def"]
        let es = EventSource(config: config, sessionType: MockDataTaskSession.self)
        await es.start()
        let session = await es.urlSession as? MockDataTaskSession
        #expect(session?.lastRequest?.url == config.url)
        #expect(session?.lastRequest?.httpMethod == config.method)
        #expect(session?.lastRequest?.httpBody == config.body)
        #expect(session?.lastRequest?.timeoutInterval == config.idleTimeout)
        #expect(session?.lastRequest?.allHTTPHeaderFields?["Accept"] == "text/event-stream")
        #expect(session?.lastRequest?.allHTTPHeaderFields?["Cache-Control"] == "no-cache")
        #expect(session?.lastRequest?.allHTTPHeaderFields?["Last-Event-Id"] == config.lastEventId)
        #expect(session?.lastRequest?.allHTTPHeaderFields?["X-LD-Header"] == "def")
        await es.stop()
        UserDefaults.eventSource.removeObject(forKey: "com.briannadoubt.event-source.last-event-id")
        UserDefaults.eventSource.synchronize()
    }

    @Test
    func startRequestIsNotReentrant() async {
        let es = EventSource(
            config: EventSource.Config(
                handler: MockHandler(),
                url: URL(string: "http://example.com")!
            ),
            sessionType: MockDataTaskSession.self
        )
        await es.start()
        await es.start()
        let session = await es.urlSession as? MockDataTaskSession
        #expect(session?.didCall_dataTask == 1)
        #expect(session?.requests.count == 1)
        await es.stop()
        UserDefaults.eventSource.removeObject(forKey: "com.briannadoubt.event-source.last-event-id")
        UserDefaults.eventSource.synchronize()
    }

    @Test
    func successfulResponseOpens() async {
        let mockHandler = MockHandler()
        
        let config = EventSource.Config(
            handler: mockHandler,
            url: URL(string: "http://example.com")!
        )
        let eventSource = EventSource(config: config, sessionType: MockDataTaskSession.self)
        await eventSource.connectForTests()
        await #expect(mockHandler.events.first == .opened)
        await eventSource.stop()
        UserDefaults.eventSource.removeObject(forKey: "com.briannadoubt.event-source.last-event-id")
        UserDefaults.eventSource.synchronize()
    }

    @Test
    func lastEventIdUpdatedByEvents() async {
        UserDefaults.eventSource.removeObject(forKey: "com.briannadoubt.event-source.last-event-id")
        
        let mockHandler = MockHandler()
        var config = EventSource.Config(handler: mockHandler, url: URL(string: "http://example.com")!)
        config.reconnectTime = 0.1
        
        let eventSource = EventSource(config: config, sessionType: MockDataTaskSession.self)
        await eventSource.start()
        await eventSource.connectForTests()
        await #expect(mockHandler.events.first == .opened)
        
        await #expect(eventSource.getLastEventId() == "")
        
        await eventSource.sendTest(
            event: """
            id: abc
            
            :comment
            
            """
        )
        
        await #expect(mockHandler.events.count == 2)
        await #expect(mockHandler.events[safe: 1] == .comment("comment"))
        await #expect(eventSource.getLastEventId() == "abc")
        
        await eventSource.endTestSession()
        
        await #expect(mockHandler.events[safe: 2] == .closed)
        
        // Expect to reconnect and include new event id
        await #expect((eventSource.urlSession as? MockDataTaskSession)?.requests.count == 2)
        await #expect((eventSource.urlSession as? MockDataTaskSession)?.requests.last?.allHTTPHeaderFields?["Last-Event-Id"] == "abc")
        await eventSource.stop()
        UserDefaults.eventSource.removeObject(forKey: "com.briannadoubt.event-source.last-event-id")
        UserDefaults.eventSource.synchronize()
    }

    @Test
    func usesRetryTime() async {
        let mockHandler = MockHandler()
        let config = EventSource.Config(
            handler: mockHandler,
            url: URL(string: "http://example.com")!,
            reconnectTime: 5 // Long enough to cause a timeout if the retry time is not updated
        )
        let eventSource = EventSource(config: config, sessionType: MockDataTaskSession.self)
        await eventSource.start()
        await eventSource.connectForTests()
        await #expect(mockHandler.events.first == .opened)
        await eventSource.sendTest(
            event: """
            retry: 100
            
            
            """
        )
        await eventSource.endTestSession()
        await #expect(mockHandler.events[safe: 1] == .closed)
        let session = await eventSource.urlSession as? MockDataTaskSession
        #expect(session?.requests.count == 2)
        await eventSource.connectForTests()
        // Expect to reconnect before this times out
        await #expect(mockHandler.events[safe: 2] == .opened)
        await eventSource.stop()
        UserDefaults.eventSource.removeObject(forKey: "com.briannadoubt.event-source.last-event-id")
        UserDefaults.eventSource.synchronize()
    }
    
    @Test
    func callsHandlerWithMessage() async {
        let mockHandler = MockHandler()
        let config = EventSource.Config(handler: mockHandler, url: URL(string: "http://example.com")!)
        let eventSource = EventSource(config: config)
        await eventSource.start()
        await eventSource.connectForTests()
        await #expect(mockHandler.events.first == .opened)
        await eventSource.sendTest(
            event: """
            event: custom
            data: {}
            
            
            """
        )
        await #expect(mockHandler.events[safe: 1] == .message("custom", MessageEvent(data: "{}")))
        await eventSource.stop()
        await #expect(mockHandler.events[safe: 2] == .closed)
        UserDefaults.eventSource.removeObject(forKey: "com.briannadoubt.event-source.last-event-id")
        UserDefaults.eventSource.synchronize()
    }

    @Test
    func testRetryOnInvalidResponseCode() async {
        let mockHandler = MockHandler()
        var config = EventSource.Config(handler: mockHandler, url: URL(string: "http://example.com")!)
        config.reconnectTime = 0.1
        let eventSource = EventSource(config: config)
        await eventSource.start()
        await eventSource.connectForTests(statusCode: 400)
        if
            case let .error(err) = await mockHandler.events[safe: 0],
            let responseErr = err as? UnsuccessfulResponseError
        {
            #expect(responseErr.responseCode == 400)
            // Expect the client to reconnect
            await eventSource.connectForTests()
            await #expect(mockHandler.events.last == .opened)
            await eventSource.stop()
        }
        UserDefaults.eventSource.removeObject(forKey: "com.briannadoubt.event-source.last-event-id")
        UserDefaults.eventSource.synchronize()
    }

    @Test
    func testShutdownByErrorHandlerOnInitialErrorResponse() async {
        let mockHandler = MockHandler()
        var config = EventSource.Config(handler: mockHandler, url: URL(string: "http://example.com")!)
        config.reconnectTime = 0.1
        config.connectionErrorHandler = { err in
            #expect((err as? UnsuccessfulResponseError)?.responseCode == 400)
            return .shutdown
        }
        let eventSource = EventSource(config: config)
        await eventSource.start()
        await eventSource.connectForTests(statusCode: 400)
        // Expect the client not to reconnect
        await #expect(mockHandler.events.isEmpty)
        await eventSource.stop()
        // Error should not have been given to the handler
        await #expect(mockHandler.events.isEmpty)
        UserDefaults.eventSource.removeObject(forKey: "com.briannadoubt.event-source.last-event-id")
        UserDefaults.eventSource.synchronize()
    }

    @Test
    func testShutdownByErrorHandlerOnResponseCompletionError() async {
        let mockHandler = MockHandler()
        var config = EventSource.Config(handler: mockHandler, url: URL(string: "http://example.com")!)
        config.reconnectTime = 0.1
        config.connectionErrorHandler = { _ in
            .shutdown
        }
        let eventSource = EventSource(config: config)
        await eventSource.start()
        await eventSource.connectForTests()
        await #expect(mockHandler.events.first == .opened)
        await eventSource.endTestSession(with: TestError())
        await #expect(mockHandler.events[safe: 1] == .closed)
        await #expect(mockHandler.events.count == 2)
        // Expect the client not to reconnect
        await eventSource.stop()
        // Error should not have been given to the handler
        await #expect(mockHandler.events.count == 2)
        UserDefaults.eventSource.removeObject(forKey: "com.briannadoubt.event-source.last-event-id")
        UserDefaults.eventSource.synchronize()
    }

    @Test
    func testShutdownBy204Response() async {
        let mockHandler = MockHandler()
        var config = EventSource.Config(handler: mockHandler, url: URL(string: "http://example.com")!)
        config.reconnectTime = 0.1
        let eventSource = EventSource(config: config)
        await eventSource.start()
        await eventSource.connectForTests(statusCode: 204)
        await #expect(mockHandler.events.isEmpty)
        await eventSource.stop()
        // Error should not have been given to the handler
        await #expect(mockHandler.events.isEmpty)
        UserDefaults.eventSource.removeObject(forKey: "com.briannadoubt.event-source.last-event-id")
        UserDefaults.eventSource.synchronize()
    }
    
    @Test
    func testCanOverride204DefaultBehavior() async {
        let mockHandler = MockHandler()
        var config = EventSource.Config(handler: mockHandler, url: URL(string: "http://example.com")!)
        config.reconnectTime = 0.1
        config.connectionErrorHandler = { err in
            #expect((err as? UnsuccessfulResponseError)?.responseCode == 204)
            return .shutdown
        }
        let eventSource = EventSource(config: config)
        await eventSource.start()
        await eventSource.connectForTests(statusCode: 204)
        // Expect the client not to reconnect
        await #expect(mockHandler.events.isEmpty)
        await eventSource.stop()
        // Error should not have been given to the handler
        await #expect(mockHandler.events.isEmpty)
        UserDefaults.eventSource.removeObject(forKey: "com.briannadoubt.event-source.last-event-id")
        UserDefaults.eventSource.synchronize()
    }
    #endif
}
