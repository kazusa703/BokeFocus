import CoreML

extension MLMultiArray {
    /// Create a zero-filled float32 tensor with the given shape
    static func zeros(shape: [Int]) -> MLMultiArray? {
        let nsShape = shape.map { NSNumber(value: $0) }
        guard let array = try? MLMultiArray(shape: nsShape, dataType: .float32) else {
            return nil
        }
        let ptr = array.dataPointer.assumingMemoryBound(to: Float.self)
        let count = shape.reduce(1, *)
        ptr.initialize(repeating: 0, count: count)
        return array
    }

    /// Read a float value at flat index
    func floatValue(at flatIndex: Int) -> Float {
        dataPointer
            .assumingMemoryBound(to: Float.self)
            .advanced(by: flatIndex)
            .pointee
    }

    /// Write a float value at flat index
    func setFloat(_ value: Float, at flatIndex: Int) {
        dataPointer
            .assumingMemoryBound(to: Float.self)
            .advanced(by: flatIndex)
            .pointee = value
    }

    /// Total element count
    var totalCount: Int {
        shape.map(\.intValue).reduce(1, *)
    }
}
