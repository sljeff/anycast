import Foundation

/// Dart's `List.sort` (dart-sdk lib/internal/sort.dart), ported verbatim:
/// ranges of at most 33 elements (`right - left <= 32`) use insertion sort,
/// larger ranges use dual-pivot quicksort. Dart's sort
/// is NOT stable, and the G7/G8 goldens byte-lock the exact order it
/// produces for feeds with duplicate pubDates — Swift's own (also unstable)
/// sort orders them differently. Comparator contract matches Dart: negative
/// = left before right.
enum DartSort {

    static let insertionSortThreshold = 32

    static func sort<T>(_ elements: inout [T], by compare: (T, T) -> Int) {
        guard elements.count > 1 else { return }
        doSort(&elements, left: 0, right: elements.count - 1, compare: compare)
    }

    static func sorted<T>(_ elements: [T], by compare: (T, T) -> Int) -> [T] {
        var copy = elements
        sort(&copy, by: compare)
        return copy
    }

    private static func doSort<T>(_ a: inout [T], left: Int, right: Int, compare: (T, T) -> Int) {
        if right - left <= insertionSortThreshold {
            insertionSort(&a, left: left, right: right, compare: compare)
        } else {
            dualPivotQuickSort(&a, left: left, right: right, compare: compare)
        }
    }

    private static func insertionSort<T>(_ a: inout [T], left: Int, right: Int, compare: (T, T) -> Int) {
        var i = left + 1
        while i <= right {
            let element = a[i]
            var j = i
            while j > left, compare(a[j - 1], element) > 0 {
                a[j] = a[j - 1]
                j -= 1
            }
            a[j] = element
            i += 1
        }
    }

    private static func dualPivotQuickSort<T>(_ a: inout [T], left: Int, right: Int, compare: (T, T) -> Int) {
        assert(right - left > insertionSortThreshold)

        // Compute the two pivots by looking at 5 elements.
        let sixth = (right - left + 1) / 6
        let index1 = left + sixth
        let index5 = right - sixth
        let index3 = (left + right) / 2
        let index2 = index3 - sixth
        let index4 = index3 + sixth

        var el1 = a[index1]
        var el2 = a[index2]
        var el3 = a[index3]
        var el4 = a[index4]
        var el5 = a[index5]

        // Sorting network for the 5 sampled elements.
        func swap(_ x: inout T, _ y: inout T) { let t = x; x = y; y = t }
        if compare(el1, el2) > 0 { swap(&el1, &el2) }
        if compare(el4, el5) > 0 { swap(&el4, &el5) }
        if compare(el1, el3) > 0 { swap(&el1, &el3) }
        if compare(el2, el3) > 0 { swap(&el2, &el3) }
        if compare(el1, el4) > 0 { swap(&el1, &el4) }
        if compare(el3, el4) > 0 { swap(&el3, &el4) }
        if compare(el2, el5) > 0 { swap(&el2, &el5) }
        if compare(el2, el3) > 0 { swap(&el2, &el3) }
        if compare(el4, el5) > 0 { swap(&el4, &el5) }

        let pivot1 = el2
        let pivot2 = el4

        a[index1] = el1
        a[index3] = el3
        a[index5] = el5
        a[index2] = a[left]
        a[index4] = a[right]

        var less = left + 1
        var great = right - 1
        let pivotsAreEqual = compare(pivot1, pivot2) == 0

        if pivotsAreEqual {
            let pivot = pivot1
            // Dutch national flag partitioning.
            var k = less
            while k <= great {
                let ak = a[k]
                var comp = compare(ak, pivot)
                if comp == 0 { k += 1; continue }
                if comp < 0 {
                    if k != less {
                        a[k] = a[less]
                        a[less] = ak
                    }
                    less += 1
                } else {
                    while true {
                        comp = compare(a[great], pivot)
                        if comp > 0 {
                            great -= 1
                            continue
                        } else if comp < 0 {
                            // Triple exchange.
                            a[k] = a[less]
                            less += 1
                            a[less - 1] = a[great]
                            a[great] = ak
                            great -= 1
                            break
                        } else {
                            a[k] = a[great]
                            a[great] = ak
                            great -= 1
                            break
                        }
                    }
                    if great < k { break }
                }
                k += 1
            }
        } else {
            // Three-way partition: < pivot1 | [pivot1, pivot2] | > pivot2.
            var k = less
            while k <= great {
                let ak = a[k]
                let compPivot1 = compare(ak, pivot1)
                if compPivot1 < 0 {
                    if k != less {
                        a[k] = a[less]
                        a[less] = ak
                    }
                    less += 1
                } else {
                    let compPivot2 = compare(ak, pivot2)
                    if compPivot2 > 0 {
                        var done = false
                        while !done {
                            let comp = compare(a[great], pivot2)
                            if comp > 0 {
                                great -= 1
                                if great < k { break }
                                continue
                            } else {
                                // a[great] <= pivot2.
                                if compare(a[great], pivot1) < 0 {
                                    // Triple exchange.
                                    a[k] = a[less]
                                    less += 1
                                    a[less - 1] = a[great]
                                    a[great] = ak
                                    great -= 1
                                } else {
                                    // a[great] >= pivot1.
                                    a[k] = a[great]
                                    a[great] = ak
                                    great -= 1
                                }
                                done = true
                            }
                        }
                    }
                }
                k += 1
            }
        }

        // Move pivots into their final positions.
        a[left] = a[less - 1]
        a[less - 1] = pivot1
        a[right] = a[great + 1]
        a[great + 1] = pivot2

        doSort(&a, left: left, right: less - 2, compare: compare)
        doSort(&a, left: great + 2, right: right, compare: compare)

        if pivotsAreEqual { return }

        if less < index1 && great > index5 {
            while compare(a[less], pivot1) == 0 { less += 1 }
            while compare(a[great], pivot2) == 0 { great -= 1 }

            // Second pass: strip pivot-equal extremes from the middle.
            var k = less
            while k <= great {
                let ak = a[k]
                let compPivot1 = compare(ak, pivot1)
                if compPivot1 == 0 {
                    if k != less {
                        a[k] = a[less]
                        a[less] = ak
                    }
                    less += 1
                } else {
                    let compPivot2 = compare(ak, pivot2)
                    if compPivot2 == 0 {
                        var done = false
                        while !done {
                            let comp = compare(a[great], pivot2)
                            if comp == 0 {
                                great -= 1
                                if great < k { break }
                                continue
                            } else {
                                // a[great] < pivot2.
                                if compare(a[great], pivot1) < 0 {
                                    // Triple exchange.
                                    a[k] = a[less]
                                    less += 1
                                    a[less - 1] = a[great]
                                    a[great] = ak
                                    great -= 1
                                } else {
                                    a[k] = a[great]
                                    a[great] = ak
                                    great -= 1
                                }
                                done = true
                            }
                        }
                    }
                }
                k += 1
            }
            doSort(&a, left: less, right: great, compare: compare)
        } else {
            doSort(&a, left: less, right: great, compare: compare)
        }
    }
}
