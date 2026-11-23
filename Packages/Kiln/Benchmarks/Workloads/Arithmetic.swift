// Workload: loops, integer and floating-point arithmetic, recursion.
// Measures the interpreter, not the parser: the work runs in `onAppear`.
import SwiftUI

func fib(_ n: Int) -> Int {
    n < 2 ? n : fib(n - 1) + fib(n - 2)
}

func primes(below limit: Int) -> Int {
    var sieve = [Bool](repeating: true, count: limit)
    var count = 0
    var i = 2
    while i < limit {
        if sieve[i] {
            count += 1
            var j = i * i
            while j < limit {
                sieve[j] = false
                j += i
            }
        }
        i += 1
    }
    return count
}

func mandelbrot(size: Int) -> Int {
    var inside = 0
    for y in 0..<size {
        for x in 0..<size {
            let cr = Double(x) / Double(size) * 3.0 - 2.0
            let ci = Double(y) / Double(size) * 2.0 - 1.0
            var zr = 0.0
            var zi = 0.0
            var n = 0
            while n < 30 && zr * zr + zi * zi < 4.0 {
                let t = zr * zr - zi * zi + cr
                zi = 2.0 * zr * zi + ci
                zr = t
                n += 1
            }
            if n == 30 { inside += 1 }
        }
    }
    return inside
}

struct ContentView: View {
    @State private var result = ""

    var body: some View {
        Text(result.isEmpty ? "Working" : result)
            .onAppear {
                result = "\(fib(16)) \(primes(below: 5000)) \(mandelbrot(size: 24))"
            }
    }
}
