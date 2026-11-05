import Foundation

enum EQPresets {
    static let frequencies: [Float] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let labels: [String] = ["31", "62", "125", "250", "500", "1K", "2K", "4K", "8K", "16K"]
    static let names: [String] = ["Flat", "Bass Boost", "Vocal", "Rock", "Electronic", "Jazz", "Classical", "Treble Boost", "Custom"]

    static let gains: [String: [Double]] = [
        "Flat": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        "Bass Boost": [7, 6, 5, 3, 1, 0, 0, 0, 0, 0],
        "Vocal": [-2, -1, 0, 2, 4, 4, 3, 1, 0, -1],
        "Rock": [5, 4, 2, 0, -1, -1, 0, 2, 4, 5],
        "Electronic": [6, 5, 2, 0, -2, 1, 1, 3, 5, 6],
        "Jazz": [4, 3, 1, 2, -1, -1, 0, 2, 3, 4],
        "Classical": [4, 3, 2, 0, -1, -1, 0, 2, 3, 4],
        "Treble Boost": [0, 0, 0, 0, 1, 2, 4, 6, 7, 8]
    ]
}
