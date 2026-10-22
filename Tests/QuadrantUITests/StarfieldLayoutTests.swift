import CoreGraphics
import QuadrantCore
import Testing

@testable import QuadrantUI

private let reference = CGSize(width: 1440, height: 900)

private func stashExclusion(_ size: CGSize) -> [CGRect] {
    [PanelGeometry(size: size).stashRect.insetBy(dx: -34, dy: -34)]
}

@Test(arguments: Edge.allCases)
func starSlotsDoNotOverlap(edge: Edge) {
    let slots = StarfieldLayout.slots(edge: edge, size: reference, exclusions: stashExclusion(reference))
    #expect(!slots.isEmpty)
    for i in slots.indices {
        for j in slots.indices where j > i {
            #expect(!slots[i].frame.intersects(slots[j].frame))
        }
    }
}

@Test(arguments: Edge.allCases)
func starSlotsStayInsideTheWedge(edge: Edge) {
    let slots = StarfieldLayout.slots(edge: edge, size: reference, exclusions: [])
    for slot in slots {
        let f = slot.frame
        for corner in [CGPoint(x: f.minX, y: f.minY), CGPoint(x: f.maxX, y: f.minY), CGPoint(x: f.minX, y: f.maxY), CGPoint(x: f.maxX, y: f.maxY)] {
            #expect(StarfieldLayout.isInside(corner, edge: edge, size: reference, inset: 0))
        }
        #expect(f.minX >= 0 && f.minY >= 0 && f.maxX <= reference.width && f.maxY <= reference.height)
    }
}

@Test(arguments: Edge.allCases)
func starSlotsKeepAwayFromExclusions(edge: Edge) {
    let exclusions = stashExclusion(reference) + [CGRect(x: 100, y: 100, width: 300, height: 200)]
    for slot in StarfieldLayout.slots(edge: edge, size: reference, exclusions: exclusions) {
        for rect in exclusions { #expect(!rect.intersects(slot.frame)) }
    }
}

@Test(arguments: Edge.allCases)
func starSlotsAreOrderedByDistanceFromCenter(edge: Edge) {
    let slots = StarfieldLayout.slots(edge: edge, size: reference, exclusions: stashExclusion(reference))
    #expect(zip(slots, slots.dropFirst()).allSatisfy { $0.distance <= $1.distance })
}

@Test(arguments: Edge.allCases)
func starCapacityGrowsWithScreenSize(edge: Edge) {
    func count(_ size: CGSize) -> Int {
        StarfieldLayout.slots(edge: edge, size: size, exclusions: stashExclusion(size)).count
    }
    let small = count(CGSize(width: 1024, height: 640))
    let medium = count(reference)
    let large = count(CGSize(width: 1920, height: 1200))
    #expect(small < medium)
    #expect(medium < large)
}

@Test func wedgeCheckSeparatesTheFourEdges() {
    let p = CGPoint(x: 100, y: 450)  // far left, vertical middle
    #expect(StarfieldLayout.isInside(p, edge: .left, size: reference, inset: 0))
    #expect(!StarfieldLayout.isInside(p, edge: .top, size: reference, inset: 0))
    #expect(!StarfieldLayout.isInside(p, edge: .right, size: reference, inset: 0))
    #expect(!StarfieldLayout.isInside(p, edge: .bottom, size: reference, inset: 0))
}
