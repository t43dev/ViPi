import Foundation

/// Ô của một phím chữ trên bàn phím (toạ độ của KeyboardView) và chữ của nó, cho SuggestLM.readTaps.
struct KeyRect {
    var x: Float, y: Float, w: Float, h: Float
    /// chữ thường a…z
    var letter: CChar
}
