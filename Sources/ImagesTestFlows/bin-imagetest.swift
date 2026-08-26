import TestFlows

@main
enum ImagesTestFlowMain {
    static func main() async {
        await TestFlowCLI.run(
            suite: ImagesFlowSuite.self
        )
    }
}
