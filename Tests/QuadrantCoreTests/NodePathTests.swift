import Testing
@testable import QuadrantCore

@Test func pathStandardizes() {
    #expect(NodePath("/a/b/").raw == "/a/b")
}
