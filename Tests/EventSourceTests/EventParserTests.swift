import Testing
@testable import EventSource

@Suite
struct EventParserTests {
    @Suite
    struct RetryTimeTests {
        @Test
        func unsetRetryReturnsConfigured() async {
            let handler = MockHandler()
            var parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
            
            parser = EventParser(handler: handler, initialEventId: "", initialRetry: 5.0)
            await #expect(parser.reset() == 5.0)
            
            await #expect(handler.maybeEvent() == nil)
        }
        
        @Test
        func setsRetryTimeToSevenSeconds() async {
            let handler = MockHandler()
            let parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
            
            await parser.parse(line: "retry: 7000")
            await #expect(parser.reset() == 7.0)
            await #expect(parser.getLastEventId() == "")
            
            await #expect(handler.maybeEvent() == nil)
        }
        
        @Test
        func retryWithNoSpace() async {
            let handler = MockHandler()
            let parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
            
            await parser.parse(line: "retry:7000")
            await #expect(parser.reset() == 7.0)
            await #expect(parser.getLastEventId() == "")
            
            await #expect(handler.maybeEvent() == nil)
        }
        
        @Test
        func doesNotSetRetryTimeUnlessEntireValueIsNumeric() async {
            let handler = MockHandler()
            let parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
            
            await parser.parse(line: "retry: 7000L")
            await #expect(parser.reset() == 1.0)
            
            await #expect(handler.maybeEvent() == nil)
        }
        
        @Test
        func safeToUseEmptyRetryTime() async {
            let handler = MockHandler()
            let parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
            
            await parser.parse(line: "retry")
            await #expect(parser.reset() == 1.0)
            
            await #expect(handler.maybeEvent() == nil)
        }
        
        @Test
        func safeToAttemptToSetRetryToOutOfBoundsValue() async {
            let handler = MockHandler()
            let parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
            
            await parser.parse(line: "retry: 10000000000000000000000000")
            await #expect(parser.reset() == 1.0)
            
            await #expect(handler.maybeEvent() == nil)
        }
        
        @Test
        func resetDoesNotResetRetry() async {
            let handler = MockHandler()
            let parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
            
            await parser.parse(line: "retry: 7000")
            await #expect(parser.reset() == 7.0)
            await #expect(parser.reset() == 7.0)
            
            await #expect(handler.maybeEvent() == nil)
        }
        
        @Test
        func testRetryNotChangedDuringOtherMessages() async {
            let handler = MockHandler()
            let parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
            
            await parser.parse(line: "retry: 7000")
            await parser.parse(line: "")
            await parser.parse(line: ":123")
            await parser.parse(line: "event: 123")
            await parser.parse(line: "data: 123")
            await parser.parse(line: "id: 123")
            await parser.parse(line: "none: 123")
            await parser.parse(line: "")
            await #expect(parser.reset() == 7.0)
            _ = await handler.maybeEvent()
            _ = await handler.maybeEvent()
            
            await #expect(handler.maybeEvent() == nil)
        }
    }

    @Suite
    struct CommentTests {
        @Test
        func emptyComment() async {
            let handler = MockHandler()
            let parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
            
            await parser.parse(line: ":")
            await #expect(handler.maybeEvent() == .comment(""))
            
            await #expect(handler.maybeEvent() == nil)
        }
        
        @Test
        func commentBody() async {
            let handler = MockHandler()
            let parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
            
            await parser.parse(line: ": comment")
            await #expect(handler.maybeEvent() == .comment(" comment"))
            
            await #expect(handler.maybeEvent() == nil)
        }
        
        @Test
        func commentCanContainColon() async {
            let handler = MockHandler()
            let parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
            
            await parser.parse(line: ":comment:line")
            await #expect(handler.maybeEvent() == .comment("comment:line"))
            
            await #expect(handler.maybeEvent() == nil)
        }
    }
    
    @Suite
    struct MessageDataTests {
        @Test
        func dispatchesEmptyMessageData() async {
            let handler = MockHandler()
            let parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
            
            await parser.parse(line: "data")
            await parser.parse(line: "")
            await parser.parse(line: "data:")
            await parser.parse(line: "")
            await parser.parse(line: "data: ")
            await parser.parse(line: "")
            await #expect(handler.maybeEvent() == .message("message", MessageEvent(data: "", lastEventId: "")))
            await #expect(handler.maybeEvent() == .message("message", MessageEvent(data: "", lastEventId: "")))
            await #expect(handler.maybeEvent() == .message("message", MessageEvent(data: "", lastEventId: "")))
            
            await #expect(handler.maybeEvent() == nil)
        }
        
        @Test
        func doesNotRemoveTrailingSpaceWhenColonNotPresent() async {
            let handler = MockHandler()
            let parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
            
            await parser.parse(line: "data ")
            await parser.parse(line: "")
            
            await #expect(handler.maybeEvent() == nil)
        }
        
        @Test
        func emptyFirstDataAppendsNewline() async {
            let handler = MockHandler()
            let parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
            
            await parser.parse(line: "data:")
            await parser.parse(line: "data:")
            await parser.parse(line: "")
            await #expect(handler.maybeEvent() == .message("message", MessageEvent(data: "\n", lastEventId: "")))
            
            await #expect(handler.maybeEvent() == nil)
        }
        
        @Test
        func dispatchesSingleLineMessage() async {
            let handler = MockHandler()
            let parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
            
            await parser.parse(line: "data: hello")
            await parser.parse(line: "")
            await #expect(handler.maybeEvent() == .message("message", MessageEvent(data: "hello", lastEventId: "")))
            
            await #expect(handler.maybeEvent() == nil)
        }
        
        @Test
        func emptyDataWithBufferedDataAppendsNewline() async {
            let handler = MockHandler()
            let parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
            
            await parser.parse(line: "data: data1")
            await parser.parse(line: "data: ")
            await parser.parse(line: "")
            await #expect(handler.maybeEvent() == .message("message", MessageEvent(data: "data1\n", lastEventId: "")))
            
            await #expect(handler.maybeEvent() == nil)
        }
        
        @Test
        func dataResetAfterEvent() async {
            let handler = MockHandler()
            let parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
            
            await parser.parse(line: "data: hello")
            await parser.parse(line: "")
            await parser.parse(line: "")
            await #expect(handler.maybeEvent() == .message("message", MessageEvent(data: "hello", lastEventId: "")))
            
            await #expect(handler.maybeEvent() == nil)
        }
        
        @Test
        func removesOnlyFirstSpace() async {
            let handler = MockHandler()
            let parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
            await parser.parse(line: "data:  {\"foo\": \"bar baz\"}")
            await parser.parse(line: "")
            await #expect(handler.maybeEvent() == .message("message", MessageEvent(data: " {\"foo\": \"bar baz\"}", lastEventId: "")))
            
            await #expect(handler.maybeEvent() == nil)
        }
        
        @Test
        func doesNotRemoveOtherWhitespace() async {
            let handler = MockHandler()
            let parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
            await parser.parse(line: "data:\t{\"foo\": \"bar baz\"}")
            await parser.parse(line: "")
            await #expect(handler.maybeEvent() == .message("message", MessageEvent(data: "\t{\"foo\": \"bar baz\"}", lastEventId: "")))
            
            await #expect(handler.maybeEvent() == nil)
        }
        
        @Test
        func allowsNoLeadingSpace() async {
            let handler = MockHandler()
            let parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
            
            await parser.parse(line: "data:{\"foo\": \"bar baz\"}")
            await parser.parse(line: "")
            await #expect(handler.maybeEvent() == .message("message", MessageEvent(data: "{\"foo\": \"bar baz\"}", lastEventId: "")))
            
            await #expect(handler.maybeEvent() == nil)
        }
        
        @Test
        func multipleDataDispatch() async {
            let handler = MockHandler()
            let parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
            
            await parser.parse(line: "data: data1")
            await parser.parse(line: "data: data2")
            await parser.parse(line: "")
            await #expect(handler.maybeEvent() == .message("message", MessageEvent(data: "data1\ndata2", lastEventId: "")))
            
            await #expect(handler.maybeEvent() == nil)
        }
    }

    @Suite
    struct EventTypeTests {
        @Test
        func dispatchesMessageWithCustomEventType() async {
            let handler = MockHandler()
            let parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
            
            await parser.parse(line: "event: customEvent")
            await parser.parse(line: "data: hello")
            await parser.parse(line: "")
            await #expect(handler.maybeEvent() == .message("customEvent", MessageEvent(data: "hello", lastEventId: "")))
            
            await #expect(handler.maybeEvent() == nil)
        }

        @Test
        func customEventTypeWithoutSpace() async {
            let handler = MockHandler()
            let parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
            
            await parser.parse(line: "event:customEvent")
            await parser.parse(line: "data: hello")
            await parser.parse(line: "")
            await #expect(handler.maybeEvent() == .message("customEvent", MessageEvent(data: "hello", lastEventId: "")))
            
            await #expect(handler.maybeEvent() == nil)
        }

        @Test
        func customEventAfterData() async {
            let handler = MockHandler()
            let parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
            
            await parser.parse(line: "data: hello")
            await parser.parse(line: "event: customEvent")
            await parser.parse(line: "")
            await #expect(handler.maybeEvent() == .message("customEvent", MessageEvent(data: "hello", lastEventId: "")))
            
            await #expect(handler.maybeEvent() == nil)
        }

        @Test
        func emptyEventTypesDefaultToMessage() async {
            let handler = MockHandler()
            let parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
            
            for event in ["event", "event:", "event: "] {
                await parser.parse(line: event)
                await parser.parse(line: "data: foo")
                await parser.parse(line: "")
            }
            
            await #expect(handler.maybeEvent() == .message("message", MessageEvent(data: "foo", lastEventId: "")))
            await #expect(handler.maybeEvent() == .message("message", MessageEvent(data: "foo", lastEventId: "")))
            await #expect(handler.maybeEvent() == .message("message", MessageEvent(data: "foo", lastEventId: "")))
            
            await #expect(handler.maybeEvent() == nil)
        }

        @Test
        func dispatchWithoutDataResetsMessageType() async {
            let handler = MockHandler()
            let parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
            
            await parser.parse(line: "event: customEvent")
            await parser.parse(line: "")
            await parser.parse(line: "data: foo")
            await parser.parse(line: "")
            await #expect(handler.maybeEvent() == .message("message", MessageEvent(data: "foo", lastEventId: "")))
            
            await #expect(handler.maybeEvent() == nil)
        }

        @Test
        func dispatchWithDataResetsMessageType() async {
            let handler = MockHandler()
            let parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
            
            await parser.parse(line: "event: customEvent")
            await parser.parse(line: "data: foo")
            await parser.parse(line: "")
            await parser.parse(line: "data: bar")
            await parser.parse(line: "")
            await #expect(handler.maybeEvent() == .message("customEvent", MessageEvent(data: "foo", lastEventId: "")))
            await #expect(handler.maybeEvent() == .message("message", MessageEvent(data: "bar", lastEventId: "")))
            
            await #expect(handler.maybeEvent() == nil)
        }
    }

    @Suite
    struct LastEventIdTests {
        @Test
        func lastEventIdNotReturnedUntilDispatch() async {
            let handler = MockHandler()
            let parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
            
            await #expect(parser.getLastEventId() == "")
            await parser.parse(line: "id: 1")
            await #expect(handler.maybeEvent() == nil)
            await #expect(parser.getLastEventId() == "")
            
            await #expect(handler.maybeEvent() == nil)
        }
        
        @Test
        func recordsLastEventIdWithoutData() async {
            let handler = MockHandler()
            let parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
            
            await parser.parse(line: "id: 1")
            await parser.parse(line: "")
            await #expect(handler.maybeEvent() == nil)
            await #expect(parser.getLastEventId() == "1")
            
            await #expect(handler.maybeEvent() == nil)
        }
        
        @Test
        func eventIdIncludedInMessageEvent() async {
            let handler = MockHandler()
            let parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
            
            await parser.parse(line: "data: hello")
            await parser.parse(line: "id: 1")
            await parser.parse(line: "")
            await #expect(handler.maybeEvent() == .message("message", MessageEvent(data: "hello", lastEventId: "1")))
            
            await #expect(handler.maybeEvent() == nil)
        }
        
        @Test
        func reusesEventIdIfNotSet() async {
            let handler = MockHandler()
            let parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
            
            await parser.parse(line: "data: hello")
            await parser.parse(line: "id: reused")
            await parser.parse(line: "")
            await parser.parse(line: "data: world")
            await parser.parse(line: "")
            await #expect(handler.maybeEvent() == .message("message", MessageEvent(data: "hello", lastEventId: "reused")))
            await #expect(handler.maybeEvent() == .message("message", MessageEvent(data: "world", lastEventId: "reused")))
            await #expect(parser.getLastEventId() == "reused")
            
            await #expect(handler.maybeEvent() == nil)
        }
        
        @Test
        func eventIdSetTwiceInEvent() async {
            let handler = MockHandler()
            let parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
            
            await parser.parse(line: "id: abc")
            await parser.parse(line: "id: def")
            await parser.parse(line: "data")
            await #expect(parser.getLastEventId() == "")
            await parser.parse(line: "")
            await #expect(handler.maybeEvent() == .message("message", MessageEvent(data: "", lastEventId: "def")))
            await #expect(parser.getLastEventId() == "def")
            
            await #expect(handler.maybeEvent() == nil)
        }
        
        @Test
        func eventIdContainingNullIgnored() async {
            let handler = MockHandler()
            let parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
            
            await parser.parse(line: "id: reused")
            await parser.parse(line: "id: abc\u{0000}def")
            await parser.parse(line: "data")
            await parser.parse(line: "")
            await #expect(handler.maybeEvent() == .message("message", MessageEvent(data: "", lastEventId: "reused")))
            await #expect(parser.getLastEventId() == "reused")
            
            await #expect(handler.maybeEvent() == nil)
        }
        
        @Test
        func resetDoesResetLastEventIdBuffer() async {
            let handler = MockHandler()
            let parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
            
            await parser.parse(line: "id: 1")
            _ = await parser.reset()
            await parser.parse(line: "data: hello")
            await parser.parse(line: "")
            await #expect(handler.maybeEvent() == .message("message", MessageEvent(data: "hello", lastEventId: "")))
            await #expect(parser.getLastEventId() == "")
            
            await #expect(handler.maybeEvent() == nil)
        }
        
        @Test
        func resetDoesNotResetLastEventId() async {
            let handler = MockHandler()
            let parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
            
            await parser.parse(line: "id: 1")
            await parser.parse(line: "")
            _ = await parser.reset()
            await parser.parse(line: "data: hello")
            await parser.parse(line: "")
            await #expect(handler.maybeEvent() == .message("message", MessageEvent(data: "hello", lastEventId: "1")))
            await #expect(parser.getLastEventId() == "1")
            
            await #expect(handler.maybeEvent() == nil)
        }
    }
    
    @Test
    func repeatedEmptyLines() async {
        let handler = MockHandler()
        let parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
        
        await parser.parse(line: "")
        await parser.parse(line: "")
        await parser.parse(line: "")
        await #expect(handler.maybeEvent() == nil)
        
        await #expect(handler.maybeEvent() == nil)
    }

    @Test
    func nothingDoneForInvalidFieldName() async {
        let handler = MockHandler()
        let parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
        
        await parser.parse(line: "invalid: bar")
        await #expect(handler.maybeEvent() == nil)
        
        await #expect(handler.maybeEvent() == nil)
    }

    @Test
    func invalidFieldNameIgnoredInEvent() async {
        let handler = MockHandler()
        let parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
        
        await parser.parse(line: "data: foo")
        await parser.parse(line: "invalid: bar")
        await parser.parse(line: "event: msg")
        await parser.parse(line: "")
        await #expect(handler.maybeEvent() == .message("msg", MessageEvent(data: "foo", lastEventId: "")))
        
        await #expect(handler.maybeEvent() == nil)
    }

    @Test
    func commentInEvent() async {
        let handler = MockHandler()
        let parser = EventParser(handler: handler, initialEventId: "", initialRetry: 1.0)
        
        await parser.parse(line: "data: foo")
        await parser.parse(line: ":bar")
        await parser.parse(line: "event: msg")
        await parser.parse(line: "")
        await #expect(handler.maybeEvent() == .comment("bar"))
        await #expect(handler.maybeEvent() == .message("msg", MessageEvent(data: "foo", lastEventId: "")))
        
        await #expect(handler.maybeEvent() == nil)
    }
}
