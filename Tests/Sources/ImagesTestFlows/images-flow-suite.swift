import TestFlows

enum ImagesFlowSuite: TestFlowRegistry {
    static let title = "Images regression flows"

    static let flows: [TestFlow] = [
        projectLayoutFlow,
        pathRenderingFlow,
        imageConfigurationSwiftContractFlow,
        imageResizeFittingFlow,
        imageConfigurationV2RoundTripFlow,
        generatedImageConfigurationFlow,
        preservedConfigurationReconciliationFlow,
        nativeCompressionFlow,
        incrementalCompressionFlow,
        compressionPrunesStaleOutputsFlow,
        compressionPathSandboxFlow,
    ]
}
