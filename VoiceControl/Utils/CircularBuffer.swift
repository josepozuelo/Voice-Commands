import Foundation

class CircularBuffer<T> {
    private var buffer: [T?]
    private var head: Int = 0
    private var count: Int = 0
    private let capacity: Int
    
    init(capacity: Int) {
        precondition(capacity > 0, "Capacity must be positive")
        self.capacity = capacity
        self.buffer = Array(repeating: nil, count: capacity)
    }
    
    var isEmpty: Bool {
        return count == 0
    }
    
    var isFull: Bool {
        return count == capacity
    }
    
    var currentCount: Int {
        return count
    }
    
    func append(_ element: T) {
        let index = (head + count) % capacity
        buffer[index] = element
        
        if count < capacity {
            count += 1
        } else {
            head = (head + 1) % capacity
        }
    }
    
    func suffix(_ count: Int) -> [T] {
        guard count > 0 else { return [] }
        let takeCount = Swift.min(count, self.count)
        
        var result: [T] = []
        result.reserveCapacity(takeCount)
        
        let startIndex = (head + self.count - takeCount + capacity) % capacity
        for i in 0..<takeCount {
            let index = (startIndex + i) % capacity
            if let element = buffer[index] {
                result.append(element)
            }
        }
        
        return result
    }
    
    func allElements() -> [T] {
        var result: [T] = []
        result.reserveCapacity(count)
        
        for i in 0..<count {
            let index = (head + i) % capacity
            if let element = buffer[index] {
                result.append(element)
            }
        }
        
        return result
    }
    
    func clear() {
        buffer = Array(repeating: nil, count: capacity)
        head = 0
        count = 0
    }
}

extension CircularBuffer: Sequence {
    func makeIterator() -> CircularBufferIterator<T> {
        return CircularBufferIterator(buffer: self)
    }
}

struct CircularBufferIterator<T>: IteratorProtocol {
    private let buffer: CircularBuffer<T>
    private var currentIndex = 0
    
    init(buffer: CircularBuffer<T>) {
        self.buffer = buffer
    }
    
    mutating func next() -> T? {
        guard currentIndex < buffer.currentCount else { return nil }
        
        let elements = buffer.allElements()
        let element = elements[currentIndex]
        currentIndex += 1
        return element
    }
}