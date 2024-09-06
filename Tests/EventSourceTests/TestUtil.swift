//
//  File.swift
//  EventSource
//
//  Created by Brianna Zamora on 9/1/24.
//

import Foundation
import Testing
@testable import EventSource

#if os(Linux) || os(Windows)
import FoundationNetworking
#endif

final class MockDataTaskSession: DataSession, @unchecked Sendable {
    init(
        configuration: URLSessionConfiguration,
        delegate: (any URLSessionDelegate)?,
        delegateQueue queue: OperationQueue?
    ) {
        self.configuration = configuration
        self.delegate = delegate
    }
    
    var configuration: URLSessionConfiguration = .default
    
    var dataResponse: (Data, URLResponse)?
    var dataChunks: [Data]? = []
    
    var requests: [URLRequest] = []
    
    weak var delegate: URLSessionDelegate?
    
    var didCall_invalidateAndCancel = 0
    func invalidateAndCancel() {
        didCall_invalidateAndCancel += 1
    }
    
    var lastRequest: URLRequest? {
        requests.last
    }
    
    var didCall_data = 0
    func data(
        for request: URLRequest,
        delegate: (any URLSessionTaskDelegate)?
    ) async throws -> (Data, URLResponse) {
        didCall_data += 1
        requests.append(request)
        return dataResponse!
    }
    
    var didCall_dataTask = 0
    func dataTask(
        with request: URLRequest,
        completionHandler: @escaping @Sendable (Data?, URLResponse?, (any Error)?) -> Void
    ) -> any DataTask {
        didCall_dataTask += 1
        requests.append(request)
        let request: URLRequest! = request
        guard let request else {
            completionHandler(nil, nil, nil)
            return MockDataTask(request: request, delegate: delegate as? URLSessionTaskDelegate)
        }
        return MockDataTask(
            request: request,
            dataChunks: dataChunks ?? [],
            delegate: delegate as? URLSessionTaskDelegate
        )
    }
}

//extension URLSession {
//    class var shared: URLSession {
//        fatalError("shared is not supported in test mocks")
//    }
//}

class MockDataTask: DataTask, @unchecked Sendable {
    var timer: Timer?
    let dataChunks: [Data]
    let request: URLRequest
    weak var session: MockDataTaskSession?
    weak var delegate: URLSessionTaskDelegate?
    
    init(request: URLRequest, dataChunks: [Data] = [], delegate: URLSessionTaskDelegate? = nil) {
        self.request = request
        self.dataChunks = dataChunks
        self.delegate = delegate
    }
    
    var didCall_resume = 0
    func resume() {
        didCall_resume += 1
    }
    
    func sendResponse(statusCode: Int) async {
        let headers = ["Content-Type": "text/event-stream; charset=utf-8", "Transfer-Encoding": "chunked"]
        let response = HTTPURLResponse(url: URL(string: "http://example.com")!, statusCode: 200, httpVersion: nil, headerFields: headers)! as URLResponse
        // Assuming delegate conforms to URLSessionDataDelegate
        if let delegate = self.delegate as? URLSessionDataDelegate {
            _ = await delegate.urlSession!(URLSession.shared, dataTask: URLSession.shared.dataTask(with: request), didReceive: response)
        }
    }
    
    func sendDataStream() async {
        let mockDataTask = URLSession.shared.dataTask(with: request)
        
        var chunkIndex = 0
        
        for _ in dataChunks {
            if chunkIndex < self.dataChunks.count {
                let chunk = self.dataChunks[chunkIndex]
                
                // Assuming delegate conforms to URLSessionDataDelegate
                if let delegate = self.delegate as? URLSessionDataDelegate {
                    delegate.urlSession?(URLSession.shared, dataTask: mockDataTask, didReceive: chunk)
                }
                
                chunkIndex += 1
            } else {
                self.timer?.invalidate() // Stop the timer when all chunks are sent
                
                // Assuming delegate conforms to URLSessionTaskDelegate
                let mockDataTask = URLSession.shared.dataTask(with: request)
                delegate?.urlSession?(URLSession.shared, task: mockDataTask, didCompleteWithError: nil)
            }
        }
    }
    
    var didCall_cancel = 0
    func cancel() {
        didCall_cancel += 1
        timer?.invalidate()
    }
}

struct EventSink<T: Sendable>: Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let queue = DispatchQueue(label: "EventSinkQueue." + UUID().uuidString)

    var receivedEvents: [T] = []

    mutating func record(_ event: T) {
        queue.sync { receivedEvents.append(event) }
        semaphore.signal()
    }

    mutating func expectEvent(maxWait: TimeInterval = 1.0) -> T? {
        switch semaphore.wait(timeout: DispatchTime.now() + maxWait) {
        case .success:
            return queue.sync {
                receivedEvents.remove(at: 0)
            }
        case .timedOut:
            #expect(Bool(false), "Expected mock handler to be called")
            return nil as T?
        }
    }

    mutating func maybeEvent() -> T? {
        switch semaphore.wait(timeout: DispatchTime.now()) {
        case .success:
            return queue.sync { receivedEvents.remove(at: 0) }
        case .timedOut:
            return nil
        }
    }

    func expectNoEvent(within: TimeInterval = 0.1) {
        if case .success = semaphore.wait(timeout: DispatchTime.now() + within) {
            #expect(receivedEvents.first == nil, "Expected no events in sink, found \(String(describing: receivedEvents.first))")
        }
    }
}

final actor RequestHandler: Sendable {
    let proto: URLProtocol
    let request: URLRequest
    let client: URLProtocolClient?

    var stopped = false

    init(proto: URLProtocol, request: URLRequest, client: URLProtocolClient?) {
        self.proto = proto
        self.request = request
        self.client = client
    }

    func respond(statusCode: Int) {
        let headers = ["Content-Type": "text/event-stream; charset=utf-8", "Transfer-Encoding": "chunked"]
        let resp = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(proto, didReceive: resp, cacheStoragePolicy: .notAllowed)
    }

    func respond(didLoad: String) {
        respond(didLoad: Data(didLoad.utf8))
    }

    func respond(didLoad: Data) {
        client?.urlProtocol(proto, didLoad: didLoad)
    }

    func finishWith(error: Error) {
        client?.urlProtocol(proto, didFailWithError: error)
    }

    func finish() {
        client?.urlProtocolDidFinishLoading(proto)
    }

    func stop() {
        stopped = true
    }
}

//class MockingProtocol: URLProtocol, @unchecked Sendable {
//    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
//    override class func canInit(with request: URLRequest) -> Bool { true }
//    override class func canInit(with task: URLSessionTask) -> Bool { true }
//
//    @MainActor
//    static var requested = EventSink<RequestHandler>()
//
//    @MainActor
//    class func resetRequested() {
//        requested = EventSink<RequestHandler>()
//    }
//
//    private var currentlyLoading: RequestHandler?
//
//    override func startLoading() {
//        Task { @MainActor in
//            let handler = RequestHandler(proto: self, request: request, client: client)
//            currentlyLoading = handler
//            Self.requested.record(handler)
//        }
//    }
//
//    override func stopLoading() {
//        Task { @MainActor in
//            await currentlyLoading?.stop()
//            currentlyLoading = nil
//        }
//    }
//}

extension URLRequest {
    func bodyStreamAsData() -> Data? {
        guard let bodyStream = self.httpBodyStream
        else { return nil }

        bodyStream.open()
        defer { bodyStream.close() }

        let bufSize: Int = 16
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buf.deallocate() }

        var data = Data()
        while bodyStream.hasBytesAvailable {
            let readDat = bodyStream.read(buf, maxLength: bufSize)
            data.append(buf, count: readDat)
        }
        return data
    }
}
