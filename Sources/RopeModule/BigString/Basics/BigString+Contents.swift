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

#if compiler(>=6.2)

@available(SwiftStdlib 6.2, *)
extension BigString {
  /// The estimated maximum number of UTF-8 code units that `BigString` is guaranteed to be able
  /// to hold without encountering an overflow in its operations. This corresponds to the capacity
  /// of the deepest tree where every node is the minimum possible size.
  public static var _minimumCapacity: Int {
    let c = _Rope._minimumCapacity
    let (r, overflow) = _Chunk.minUTF8Count.multipliedReportingOverflow(by: c)
    guard !overflow else { return Int.max }
    return r
  }

  /// The maximum number of UTF-8 code units that `BigString` may be able to store in the best
  /// possible case, when every node in the underlying tree is fully filled with data.
  public static var _maximumCapacity: Int {
    let c = _Rope._maximumCapacity
    let (r, overflow) = _Chunk.maxUTF8Count.multipliedReportingOverflow(by: c)
    guard !overflow else { return Int.max }
    return r
  }
}

@available(SwiftStdlib 6.2, *)
extension BigString {
  var _characterCount: Int { _rope.summary.characters }
  var _unicodeScalarCount: Int { _rope.summary.unicodeScalars }
  var _utf16Count: Int { _rope.summary.utf16 }
  var _utf8Count: Int { _rope.summary.utf8 }
}

@available(SwiftStdlib 6.2, *)
extension BigString {
  func _distance(
    from start: Index,
    to end: Index,
    in metric: some _StringMetric
  ) -> Int {
    precondition(start <= endIndex && end <= endIndex, "Invalid index")
    guard start != end else { return 0 }
    assert(!isEmpty)
    let (lesser, greater) = (start <= end ? (start, end) : (end, start))
    let a = resolve(lesser, preferEnd: false)
    let b = resolve(greater, preferEnd: false)

    let ropeIndexA = a._rope!
    let ropeIndexB = b._rope!
    let chunkIndexA = a._chunkIndex
    let chunkIndexB = b._chunkIndex
    assert(ropeIndexA != _rope.endIndex) // Handled above

    var d = 0
    if ropeIndexA == ropeIndexB {
      d = metric.distance(from: chunkIndexA, to: chunkIndexB, in: _rope[ropeIndexA])
    } else {
      d = _rope.distance(from: ropeIndexA, to: ropeIndexB, in: metric)
      d -= metric.prefixSize(to: chunkIndexA, in: _rope[ropeIndexA])
      if ropeIndexB != _rope.endIndex {
        d += metric.prefixSize(to: chunkIndexB, in: _rope[ropeIndexB])
      }
    }
    return start <= end ? d : -d
  }

  func _characterDistance(from start: Index, to end: Index) -> Int {
    let start = _characterIndex(roundingDown: start)
    let end = _characterIndex(roundingDown: end)
    return _distance(from: start, to: end, in: _CharacterMetric())
  }

  func _unicodeScalarDistance(from start: Index, to end: Index) -> Int {
    _distance(from: start, to: end, in: _UnicodeScalarMetric())
  }

  func _utf16Distance(from start: Index, to end: Index) -> Int {
    _distance(from: start, to: end, in: _UTF16Metric())
  }

  func _utf8Distance(from start: Index, to end: Index) -> Int {
    end.utf8Offset - start.utf8Offset
  }
}

@available(SwiftStdlib 6.2, *)
extension BigString {
  // FIXME: See if we need direct implementations for these.

  func _characterOffset(of index: Index) -> Int {
    let index = _characterIndex(roundingDown: index)
    return _characterDistance(from: startIndex, to: index)
  }

  func _unicodeScalarOffset(of index: Index) -> Int {
    _unicodeScalarDistance(from: startIndex, to: index)
  }

  func _utf16Offset(of index: Index) -> Int {
    _utf16Distance(from: startIndex, to: index)
  }

  func _utf8Offset(of index: Index) -> Int {
    _utf8Distance(from: startIndex, to: index)
  }
}

@available(SwiftStdlib 6.2, *)
extension BigString {
  // FIXME: See if we need direct implementations for these.

  func _characterIndex(at offset: Int) -> Index {
    _characterIndex(startIndex, offsetBy: offset)
  }

  func _unicodeScalarIndex(at offset: Int) -> Index {
    _unicodeScalarIndex(startIndex, offsetBy: offset)
  }

  func _utf16Index(at offset: Int) -> Index {
    _utf16Index(startIndex, offsetBy: offset)
  }

  func _utf8Index(at offset: Int) -> Index {
    _utf8Index(startIndex, offsetBy: offset)
  }
}

@available(SwiftStdlib 6.2, *)
extension BigString {
  func _index(
    _ i: Index,
    offsetBy distance: Int,
    in metric: some _StringMetric
  ) -> Index {
    precondition(i <= endIndex, "Index out of bounds")
    if isEmpty {
      precondition(distance == 0, "Index out of bounds")
      return startIndex
    }
    if i == endIndex, distance == 0 { return i }
    let i = resolve(i, preferEnd: i == endIndex || distance < 0)
    var ri = i._rope!
    var ci = i._chunkIndex
    var d = distance
    var chunk = _rope[ri]
    let r = metric.formIndex(&ci, offsetBy: &d, in: chunk)
    if r.found {
      return Index(baseUTF8Offset: i._utf8BaseOffset, _rope: ri, chunk: ci)
    }

    if r.forward {
      assert(distance >= 0)
      assert(ci == chunk.endIndex)
      d += metric._nonnegativeSize(of: chunk.summary)
      let start = ri
      _rope.formIndex(&ri, offsetBy: &d, in: metric, preferEnd: false)
      if ri == _rope.endIndex {
        return endIndex
      }
      chunk = _rope[ri]
      ci = metric.index(at: d, in: chunk)
      let base = i._utf8BaseOffset + _rope.distance(from: start, to: ri, in: _UTF8Metric())
      return Index(baseUTF8Offset: base, _rope: ri, chunk: ci)
    }

    assert(distance <= 0)
    assert(ci == chunk.startIndex)
    let start = ri
    _rope.formIndex(&ri, offsetBy: &d, in: metric, preferEnd: false)
    chunk = _rope[ri]
    ci = metric.index(at: d, in: chunk)
    let base = i._utf8BaseOffset + _rope.distance(from: start, to: ri, in: _UTF8Metric())
    return Index(baseUTF8Offset: base, _rope: ri, chunk: ci)
  }

  func _characterIndex(_ i: Index, offsetBy distance: Int) -> Index {
    let i = _characterIndex(roundingDown: i)
    let result = _index(i, offsetBy: distance, in: _CharacterMetric())
    return result._knownCharacterAligned()
  }

  func _unicodeScalarIndex(_ i: Index, offsetBy distance: Int) -> Index {
    _index(i, offsetBy: distance, in: _UnicodeScalarMetric())._knownScalarAligned()
  }

  func _utf16Index(_ i: Index, offsetBy distance: Int) -> Index {
    _index(i, offsetBy: distance, in: _UTF16Metric())
  }

  func _utf8Index(_ i: Index, offsetBy distance: Int) -> Index {
    _index(i, offsetBy: distance, in: _UTF8Metric())
  }
}

@available(SwiftStdlib 6.2, *)
extension BigString {
  func _index(
    _ i: Index,
    offsetBy distance: Int,
    limitedBy limit: Index,
    in metric: some _StringMetric
  ) -> Index? {
    // FIXME: Do we need a direct implementation?
    if distance >= 0 {
      if limit >= i {
        let d = self._distance(from: i, to: limit, in: metric)
        if d < distance { return nil }
      }
    } else {
      if limit <= i {
        let d = self._distance(from: i, to: limit, in: metric)
        if d > distance { return nil }
      }
    }
    return self._index(i, offsetBy: distance, in: metric)
  }

  func _characterIndex(_ i: Index, offsetBy distance: Int, limitedBy limit: Index) -> Index? {
    let i = _characterIndex(roundingDown: i)
    let limit = _characterIndex(roundingDown: limit)
    guard let j = _index(i, offsetBy: distance, limitedBy: limit, in: _CharacterMetric()) else {
      return nil
    }
    return j._knownCharacterAligned()
  }

  func _unicodeScalarIndex(_ i: Index, offsetBy distance: Int, limitedBy limit: Index) -> Index? {
    guard let j = _index(i, offsetBy: distance, limitedBy: limit, in: _UnicodeScalarMetric()) else {
      return nil
    }
    return j._knownScalarAligned()
  }

  func _utf16Index(_ i: Index, offsetBy distance: Int, limitedBy limit: Index) -> Index? {
    _index(i, offsetBy: distance, limitedBy: limit, in: _UTF16Metric())
  }

  func _utf8Index(_ i: Index, offsetBy distance: Int, limitedBy limit: Index) -> Index? {
    _index(i, offsetBy: distance, limitedBy: limit, in: _UTF8Metric())
  }
}

@available(SwiftStdlib 6.2, *)
extension BigString {
  func _characterIndex(after i: Index) -> Index {
    let i = _characterIndex(roundingDown: i)
    return _index(i, offsetBy: 1, in: _CharacterMetric())._knownCharacterAligned()
  }

  func _unicodeScalarIndex(after i: Index) -> Index {
    _index(i, offsetBy: 1, in: _UnicodeScalarMetric())._knownScalarAligned()
  }

  func _utf16Index(after i: Index) -> Index {
    _index(i, offsetBy: 1, in: _UTF16Metric())
  }

  func _utf8Index(after i: Index) -> Index {
    precondition(i < endIndex, "Can't advance above end index")
    let i = resolve(i, preferEnd: false)
    let ri = i._rope!
    var ci = i._chunkIndex
    let chunk = _rope[ri]
    ci.utf8Offset += 1
    if ci == chunk.endIndex {
      return Index(
        baseUTF8Offset: i._utf8BaseOffset + chunk.utf8Count,
        _rope: _rope.index(after: ri),
        chunk: BigString._Chunk.Index(utf8Offset: 0))
    }
    return Index(_utf8Offset: i.utf8Offset + 1, _rope: ri, chunkOffset: ci.utf8Offset)
  }
}

@available(SwiftStdlib 6.2, *)
extension BigString {
  func _characterIndex(before i: Index) -> Index {
    let i = _characterIndex(roundingDown: i)
    return _index(i, offsetBy: -1, in: _CharacterMetric())._knownCharacterAligned()
  }

  func _unicodeScalarIndex(before i: Index) -> Index {
    _index(i, offsetBy: -1, in: _UnicodeScalarMetric())._knownScalarAligned()
  }

  func _utf16Index(before i: Index) -> Index {
    _index(i, offsetBy: -1, in: _UTF16Metric())
  }

  func _utf8Index(before i: Index) -> Index {
    precondition(i > startIndex, "Can't advance below start index")
    let i = resolve(i, preferEnd: true)
    var ri = i._rope!
    let ci = i._chunkIndex
    if ci.utf8Offset > 0 {
      return Index(
        _utf8Offset: i.utf8Offset &- 1,
        _rope: ri,
        chunkOffset: ci.utf8Offset &- 1)
    }
    _rope.formIndex(before: &ri)
    let chunk = _rope[ri]
    return Index(
      baseUTF8Offset: i._utf8BaseOffset - chunk.utf8Count,
      _rope: ri,
      chunk: BigString._Chunk.Index(utf8Offset: chunk.utf8Count - 1))
  }
}

@available(SwiftStdlib 6.2, *)
extension BigString {
  func _characterIndex(roundingDown i: Index) -> Index {
    let offset = i.utf8Offset
    precondition(offset >= 0 && offset <= _utf8Count, "Index out of bounds")
    guard offset > 0 else { return resolve(i, preferEnd: false)._knownCharacterAligned() }
    guard offset < _utf8Count else { return resolve(i, preferEnd: true)._knownCharacterAligned() }

    let i = resolve(i, preferEnd: false)
    guard !i._chunkIndex.isKnownCharacterAligned else {
      return i
    }

    var ri = i._rope!
    let ci = i._chunkIndex
    var chunk = _rope[ri]
    if chunk.hasBreaks {
      let first = chunk.firstBreak
      let last = chunk.lastBreak
      if ci == first || ci == last { return i._knownCharacterAligned() }
      if ci > last {
        return Index(
          baseUTF8Offset: i._utf8BaseOffset, _rope: ri, chunk: last
        )._knownCharacterAligned()
      }
      if ci > first {
        let j = chunk.characterIndex(roundingDown: ci)
        return Index(baseUTF8Offset: i._utf8BaseOffset, _rope: ri, chunk: j)._knownCharacterAligned()
      }
    }

    var baseOffset = i._utf8BaseOffset
    while ri > self._rope.startIndex {
      self._rope.formIndex(before: &ri)
      chunk = self._rope[ri]
      baseOffset -= chunk.utf8Count
      if chunk.hasBreaks { break }
    }
    return Index(
      baseUTF8Offset: baseOffset, _rope: ri, chunk: chunk.lastBreak
    )._knownCharacterAligned()
  }

  func _unicodeScalarIndex(roundingDown i: Index) -> Index {
    precondition(i <= endIndex, "Index out of bounds")
    guard i > startIndex else { return resolve(i, preferEnd: false)._knownCharacterAligned() }
    guard i < endIndex else { return resolve(i, preferEnd: true)._knownCharacterAligned() }

    let start = self.resolve(i, preferEnd: false)
    guard !i._chunkIndex.isKnownScalarAligned else { return resolve(i, preferEnd: false) }
    let ri = start._rope!
    let chunk = self._rope[ri]
    let ci = chunk.scalarIndex(roundingDown: start._chunkIndex)
    return Index(baseUTF8Offset: start._utf8BaseOffset, _rope: ri, chunk: ci)._knownScalarAligned()
  }

  func _utf8Index(roundingDown i: Index) -> Index {
    precondition(i <= endIndex, "Index out of bounds")
    guard i < endIndex else { return endIndex }
    var r = i
    if i._chunkIndex.isUTF16TrailingSurrogate {
      r._clearUTF16TrailingSurrogate()
    }
    return resolve(r, preferEnd: false)
  }

  func _utf16Index(roundingDown i: Index) -> Index {
    if i._chunkIndex.isUTF16TrailingSurrogate {
      precondition(i < endIndex, "Index out of bounds")
      // (We know i can't be the endIndex -- it addresses a trailing surrogate.)
      return self.resolve(i, preferEnd: false)
    }
    return _unicodeScalarIndex(roundingDown: i)
  }
}

@available(SwiftStdlib 6.2, *)
extension BigString {
  func _characterIndex(roundingUp i: Index) -> Index {
    let j = _characterIndex(roundingDown: i)
    if i == j { return j }
    return _characterIndex(after: j)
  }

  func _unicodeScalarIndex(roundingUp i: Index) -> Index {
    let j = _unicodeScalarIndex(roundingDown: i)
    if i == j { return j }
    return _unicodeScalarIndex(after: j)
  }

  func _utf8Index(roundingUp i: Index) -> Index {
    // Note: this orders UTF-16 trailing surrogate indices in between the first and second byte
    // of the UTF-8 encoding.
    let j = _utf8Index(roundingDown: i)
    if i == j { return j }
    return _utf8Index(after: j)
  }

  func _utf16Index(roundingUp i: Index) -> Index {
    // Note: if `i` addresses some byte in the middle of a non-BMP scalar then the result will
    // point to the trailing surrogate.
    let j = _utf16Index(roundingDown: i)
    if i == j { return j }
    return _utf16Index(after: j)
  }
}

@available(SwiftStdlib 6.2, *)
extension BigString {
  func _character(at start: Index) -> (character: Character, end: Index) {
    let start = _characterIndex(roundingDown: start)
    precondition(start.utf8Offset < _utf8Count, "Index out of bounds")

    var ri = start._rope!
    var ci = start._chunkIndex
    var chunk = _rope[ri]

    // Fast path: The entire character lives within the chunk
    if chunk.hasBreaks, (chunk.firstBreak..<chunk.lastBreak).contains(ci) {
      let endCi = chunk.characterIndex(after: ci)
      let offset = endCi.utf8Offset - ci.utf8Offset
      let endIndex = Index(
        _utf8Offset: start.utf8Offset + offset,
        utf16TrailingSurrogate: endCi.isUTF16TrailingSurrogate,
        _rope: ri,
        chunkOffset: endCi.utf8Offset
      )._knownCharacterAligned()
      return (chunk[character: ci], endIndex)
    }

    var s = String(copying: chunk.suffix)
    var base = start.utf8Offset + chunk.suffix.count

    while true {
      _rope.formIndex(after: &ri)
      guard ri < _rope.endIndex else {
        ci = _Chunk.Index(utf8Offset: 0)
        break
      }
      chunk = _rope[ri]

      s.append(copying: chunk.prefix)
      base += chunk.prefix.count

      if chunk.hasBreaks {
        ci = chunk.firstBreak
        break
      }
    }

    return (
      Character(s),
      Index(
        _utf8Offset: base,
        utf16TrailingSurrogate: ci.isUTF16TrailingSurrogate,
        _rope: ri,
        chunkOffset: ci.utf8Offset
      )._knownCharacterAligned()
    )
  }

  subscript(_utf8 index: Index) -> UInt8 {
    precondition(index < endIndex, "Index out of bounds")
    let index = resolve(index, preferEnd: false)
    return _rope[index._rope!][utf8: index._chunkIndex]
  }

  subscript(_utf8 offset: Int) -> UInt8 {
    precondition(offset >= 0 && offset < _utf8Count, "Offset out of bounds")
    let index = _utf8Index(at: offset)
    return self[_utf8: index]
  }

  subscript(_utf16 index: Index) -> UInt16 {
    precondition(index < endIndex, "Index out of bounds")
    let index = resolve(index, preferEnd: false)
    return _rope[index._rope!][utf16: index._chunkIndex]
  }

  subscript(_utf16 offset: Int) -> UInt16 {
    precondition(offset >= 0 && offset < _utf16Count, "Offset out of bounds")
    let index = _utf16Index(at: offset)
    return self[_utf16: index]
  }

  subscript(_character index: Index) -> Character {
    _character(at: index).character
  }

  subscript(_character offset: Int) -> Character {
    precondition(offset >= 0 && offset < _utf8Count, "Offset out of bounds")
    return _character(at: Index(_utf8Offset: offset)).character
  }

  subscript(_unicodeScalar index: Index) -> Unicode.Scalar {
    precondition(index < endIndex, "Index out of bounds")
    let index = resolve(index, preferEnd: false)
    return _rope[index._rope!][scalar: index._chunkIndex]
  }

  subscript(_unicodeScalar offset: Int) -> Unicode.Scalar {
    precondition(offset >= 0 && offset < _unicodeScalarCount, "Offset out of bounds")
    let index = _unicodeScalarIndex(at: offset)
    return self[_unicodeScalar: index]
  }
}

@available(SwiftStdlib 6.2, *)
extension BigString {
  func _foreachChunk(
    from start: Index,
    to end: Index,
    _ body: (UnsafeBufferPointer<UInt8>) -> Void
  ) {
    precondition(start <= end)
    guard start < end else { return }
    let start = resolve(start, preferEnd: false)
    let end = resolve(end, preferEnd: true)

    var ri = start._rope!
    let endRopeIndex = end._rope!

    if ri == endRopeIndex {
      let buffer = _rope[ri]._bytes.extracting(start._chunkIndex.utf8Offset ..< end._chunkIndex.utf8Offset)
      body(buffer)
      return
    }

    body(_rope[ri]._bytes.extracting(start._chunkIndex.utf8Offset...))

    _rope.formIndex(after: &ri)
    while ri < endRopeIndex {
      body(_rope[ri]._bytes)
    }

    body(_rope[ri]._bytes.extracting(..<end._chunkIndex.utf8Offset))
  }
}

#endif // compiler(>=6.2)
