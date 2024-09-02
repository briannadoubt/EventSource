import Foundation
import os

public actor EventSource: NSObject {
    static let logger: Logger = Logger(
        subsystem: "EventSource",
        category: "EventSource"
    )
    
    public let config: Config
    
    private(set) var readyState: ReadyState = .raw
    func set(readyState: ReadyState) {
        self.readyState = readyState
    }
    private var urlSession: URLSession?
    let utf8LineParser: UTF8LineParser = UTF8LineParser()
    let eventParser: EventParser
    let reconnectionTimer: ReconnectionTimer
    private var sessionTask: URLSessionDataTask?
    
    private var delegate: EventSourceDelegate?
    
    func createSession() -> URLSession {
        URLSession(
            configuration: config.urlSessionConfiguration,
            delegate: delegate,
            delegateQueue: nil
        )
    }

    public init(config: Config) {
        self.config = config
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
            Self.logger.info("start() called on already-started EventSource object. Returning")
            return
        }
        self.readyState = .connecting
        self.urlSession = self.createSession()
        await self.connect()
    }

    public func stop() async {
        let previousState = self.readyState
        self.readyState = .shutdown
        self.sessionTask?.cancel()
        if previousState == .open {
            await self.config.handler.onClosed()
        }
        self.urlSession?.invalidateAndCancel()
        self.urlSession = nil
    }
    
    func connect() async {
        Self.logger.info("Starting EventSource client")
        let request = await createRequest()
        let task = urlSession?.dataTask(with: request)
        task?.resume()
        sessionTask = task
    }

    public func getLastEventId() async -> String? {
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
        if let lastEventId = await self.getLastEventId(), !lastEventId.isEmpty {
            urlRequest.setValue(lastEventId, forHTTPHeaderField: "Last-Event-Id")
        }
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
        public var headers: [String: String] = [:]
        /// Transform function to allow dynamically configuring the headers on each API request.
        public var headerTransform: HeaderTransform = { $0 }
        /// An initial value for the last-event-id header to be sent on the initial request
        public var lastEventId: String = ""
        
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
                let sessionConfig = _urlSessionConfiguration.copy() as! URLSessionConfiguration
                sessionConfig.httpAdditionalHeaders = ["Accept": "text/event-stream", "Cache-Control": "no-cache"]
                sessionConfig.timeoutIntervalForRequest = idleTimeout

                #if !os(Linux) && !os(Windows)
                if #available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *) {
                    sessionConfig.tlsMinimumSupportedProtocolVersion = .TLSv12
                } else {
                    sessionConfig.tlsMinimumSupportedProtocol = .tlsProtocol12
                }
                #endif
                return sessionConfig
            }
            set {
                // swiftlint:disable:next force_cast
                _urlSessionConfiguration = newValue.copy() as! URLSessionConfiguration
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
        public init(handler: EventHandler, url: URL, lastEventId: String? = nil) {
            self.handler = handler
            self.url = url
            self.lastEventId = lastEventId ?? ""
        }
    }
}
