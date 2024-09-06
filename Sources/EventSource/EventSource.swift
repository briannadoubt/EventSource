import Foundation
import os

extension UserDefaults {
    public static var eventSource: UserDefaults {
        UserDefaults(suiteName: "com.briannadoubt.event-source") ?? .standard
    }
}

protocol DataSession: Sendable {
    func data(
        for request: URLRequest,
        delegate: (any URLSessionTaskDelegate)?
    ) async throws -> (Data, URLResponse)
    
    func dataTask(
        with request: URLRequest,
        completionHandler: @escaping @Sendable (Data?, URLResponse?, (any Error)?) -> Void
    ) -> DataTask
    
    func invalidateAndCancel()
    
    var configuration: URLSessionConfiguration { get }
    
    init(configuration: URLSessionConfiguration, delegate: (any URLSessionDelegate)?, delegateQueue queue: OperationQueue?)
}

public protocol DataTask: AnyObject {
    func resume()
    func cancel()
}

extension URLSessionDataTask: DataTask {}

extension DataSession {
    /// Convenience method to load data using a URLRequest, creates and resumes a URLSessionDataTask internally.
    ///
    /// - Parameter request: The URLRequest for which to load data.
    /// - Parameter delegate: Task-specific delegate. Defaults to `nil`.
    /// - Returns: Data and response.
    public func data(
        for request: URLRequest,
        delegate: (any URLSessionTaskDelegate)? = nil
    ) async throws -> (Data, URLResponse) {
        try await data(for: request, delegate: delegate)
    }
    
    func dataTask(
        with request: URLRequest,
        completionHandler: @escaping @Sendable (Data?, URLResponse?, (any Error)?) -> Void = { _, _, _ in }
    ) -> DataTask {
        dataTask(with: request, completionHandler: completionHandler)
    }
}

extension URLSession: DataSession {
    public func dataTask(
        with request: URLRequest,
        completionHandler: @escaping @Sendable (Data?, URLResponse?, (any Error)?) -> Void
    ) -> any DataTask {
        dataTask(
            with: request,
            completionHandler: completionHandler
        ) as URLSessionDataTask
    }
}

public actor EventSource: NSObject {
    static var logger: Logger {
        Logger(
            subsystem: "EventSource",
            category: "EventSource"
        )
    }
    
    public let config: Config
    
    private(set) var readyState: ReadyState = .raw
    func set(readyState: ReadyState) {
        self.readyState = readyState
    }
    var urlSession: (any DataSession)?
    let utf8LineParser: UTF8LineParser = UTF8LineParser()
    let eventParser: EventParser
    let reconnectionTimer: ReconnectionTimer
    var sessionTask: DataTask?
    
    var delegate: EventSourceDelegate?
    
    let sessionType: any DataSession.Type
    func createSession<Session: DataSession>(as: Session.Type) -> any DataSession {
        Session.init(
            configuration: config.urlSessionConfiguration,
            delegate: delegate,
            delegateQueue: nil
        )
    }

    public init(config: Config) {
        self.init(config: config, sessionType: URLSession.self)
    }
    
    init(config: Config, sessionType: any DataSession.Type) {
        self.config = config
        self.sessionType = sessionType
        self.eventParser = EventParser(
            handler: config.handler,
            initialEventId: config.lastEventId,
            initialRetry: config.reconnectTime
        )
        self.reconnectionTimer = ReconnectionTimer(
            maxDelay: config.maxReconnectTime,
            resetInterval: config.backoffResetThreshold
        )
        super.init()
        self.delegate = EventSourceDelegate(eventSource: self)
    }

    public func start() async {
        guard self.readyState == .raw else {
            Self.logger.warning("start() called on already-started EventSource object.")
            return
        }
        self.readyState = .connecting
        if urlSession == nil {
            self.urlSession = self.createSession(as: sessionType)
        }
        await self.connect()
    }

    public func stop() async {
        let previousState = self.readyState
        self.readyState = .shutdown
        self.sessionTask?.cancel()
        self.sessionTask = nil
        if previousState == .open {
            await self.config.handler.onClosed()
        }
        self.urlSession?.invalidateAndCancel()
        UserDefaults.eventSource.removeObject(forKey: "com.briannadoubt.event-source.last-event-id")
    }
    
    func connect() async {
        Self.logger.info("Starting EventSource client")
        let request = await createRequest()
        let task = urlSession?.dataTask(with: request)
        task?.resume()
        sessionTask = task
    }

    public func getLastEventId() async -> String {
        await eventParser.getLastEventId()
    }

    func createRequest() async -> URLRequest {
        var urlRequest = URLRequest(
            url: self.config.url,
            cachePolicy: URLRequest.CachePolicy.reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: self.config.idleTimeout
        )
        urlRequest.httpMethod = self.config.method
        urlRequest.httpBody = self.config.body
        let lastEventId = await self.getLastEventId()
        if !lastEventId.isEmpty {
            urlRequest.setValue(lastEventId, forHTTPHeaderField: "Last-Event-Id")
        }
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        urlRequest.allHTTPHeaderFields = self.config.headerTransform(
            urlRequest.allHTTPHeaderFields?.merging(self.config.headers) { $1 } ?? self.config.headers
        )
        return urlRequest
    }
    
    func dispatchError(error: Error) async -> ConnectionErrorAction {
        let action: ConnectionErrorAction = await config.connectionErrorHandler(error)
        if action != .shutdown {
            await config.handler.onError(error: error)
        }
        return action
    }
    
    /// Struct for configuring the EventSource.
    public struct Config: Sendable {
        /// The `EventHandler` called in response to activity on the stream.
        public let handler: EventHandler
        /// The `URL` of the request used when connecting to the EventSource API.
        public let url: URL

        /// The HTTP method to use for the API request.
        public var method: String = "GET"
        /// Optional HTTP body to be included in the API request.
        public var body: Data?
        /// Additional HTTP headers to be set on the request
        public var headers: [String: String] =  [:]
        /// Transform function to allow dynamically configuring the headers on each API request.
        public var headerTransform: HeaderTransform = { $0 }
        /// An initial value for the last-event-id header to be sent on the initial request
        public var lastEventId: String
        
        /// The minimum amount of time to wait before reconnecting after a failure
        public var reconnectTime: TimeInterval = 1.0
        /// The maximum amount of time to wait before reconnecting after a failure
        public var maxReconnectTime: TimeInterval = 30.0
        /// The minimum amount of time for an `EventSource` connection to remain open before allowing the connection
        /// backoff to reset.
        public var backoffResetThreshold: TimeInterval = 60.0
        /// The maximum amount of time between receiving any data before considering the connection to have timed out.
        public var idleTimeout: TimeInterval = 300.0

        private var _urlSessionConfiguration: URLSessionConfiguration = URLSessionConfiguration.default
        /**
         The `URLSessionConfiguration` used to create the `URLSession`.

         - Important:
            Note that this copies the given `URLSessionConfiguration` when set, and returns copies (updated with any
         overrides specified by other configuration options) when the value is retrieved. This prevents updating the
         `URLSessionConfiguration` after initializing `EventSource` with the `Config`, and prevents the `EventSource`
         from updating any properties of the given `URLSessionConfiguration`.

         - Since: 1.3.0
         */
        public var urlSessionConfiguration: URLSessionConfiguration {
            get {
                // swiftlint:disable:next force_cast
                let sessionConfig = _urlSessionConfiguration.copy() as? URLSessionConfiguration
                sessionConfig?.httpAdditionalHeaders = ["Accept": "text/event-stream", "Cache-Control": "no-cache"]
                sessionConfig?.timeoutIntervalForRequest = idleTimeout

                #if !os(Linux) && !os(Windows)
                if #available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *) {
                    sessionConfig?.tlsMinimumSupportedProtocolVersion = .TLSv12
                } else {
                    sessionConfig?.tlsMinimumSupportedProtocol = .tlsProtocol12
                }
                #endif
                return sessionConfig ?? .default
            }
            set {
                // swiftlint:disable:next force_cast
                _urlSessionConfiguration = newValue.copy() as? URLSessionConfiguration ?? .default
            }
        }

        /**
         An error handler that is called when an error occurs and can shut down the client in response.

         The default error handler will always attempt to reconnect on an
         error, unless `EventSource.stop()` is called or the error code is 204.
         */
        public var connectionErrorHandler: ConnectionErrorHandler = { error in
            guard let unsuccessfulResponseError = error as? UnsuccessfulResponseError
            else { return .proceed }

            let responseCode: Int = unsuccessfulResponseError.responseCode
            if 204 == responseCode {
                return .shutdown
            }
            return .proceed
        }

        /// Create a new configuration with an `EventHandler` and a `URL`
        public init(handler: EventHandler, url: URL, lastEventId: String? = nil, reconnectTime: TimeInterval = 1) {
            self.handler = handler
            self.url = url
            self.lastEventId = lastEventId ?? ""
            self.reconnectTime = reconnectTime
        }
    }
}
