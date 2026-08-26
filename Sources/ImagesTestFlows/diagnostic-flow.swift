import TestFlows

func diagnosticFlow(
    _ id: String,
    title: String? = nil,
    tags: Set<String> = [],
    skip: String? = nil,
    expectedFailure: String? = nil,
    operation: @escaping @Sendable () async throws -> [TestFlowDiagnostic]
) -> TestFlow {
    TestFlow(
        id,
        title: title,
        tags: tags,
        skip: skip,
        expectedFailure: expectedFailure,
        operation: operation
    )
}
