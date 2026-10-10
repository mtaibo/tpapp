import Testing

/// Child suites share `StubURLProtocol.handler`; serializing this parent keeps them from racing each other.
@Suite(.serialized) struct TPCoreTestsRoot {}
