//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Collections open source project
//
// Copyright (c) 2023 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

@available(SwiftStdlib 6.2, *)
extension BigString {
  mutating func _removeSubrange(_ bounds: Range<Index>) {
    precondition(bounds.upperBound <= endIndex, "Index out of bounds")
    if bounds.isEmpty { return }
    let lower = bounds.lowerBound.utf8Offset
    let upper = bounds.upperBound.utf8Offset
    _rope.removeSubrange(lower ..< upper, in: _UTF8Metric())
  }
}

@available(SwiftStdlib 6.2, *)
extension BigString {
  mutating func removeCharacter(at i: Index) -> Character {
    let start = self.resolve(i, preferEnd: false)
    let (character, end) = self._character(at: start)
    self.removeSubrange(start ..< end)
    return character
  }

  mutating func removeUnicodeScalar(at i: Index) -> Unicode.Scalar {
    precondition(i < endIndex, "Index out of bounds")
    let start = _unicodeScalarIndex(roundingDown: i)
    let ropeIndex = start._rope!
    let chunkIndex = start._chunkIndex
    let chunk = _rope[ropeIndex]
    let scalar = chunk[scalar: chunkIndex]
    let next = chunk.scalarIndex(after: chunkIndex)
    let end = Index(baseUTF8Offset: start._utf8BaseOffset, _rope: ropeIndex, chunk: next)
    self.removeSubrange(start ..< end)
    return scalar
  }
}
