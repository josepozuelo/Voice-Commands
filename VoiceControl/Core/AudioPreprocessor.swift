import Foundation
import AVFoundation

class AudioPreprocessor {
    private let targetSampleRate: Int
    private let frameDuration: TimeInterval
    private let samplesPerFrame: Int
    
    init(targetSampleRate: Int = Config.vadSampleRate, 
         frameDuration: TimeInterval = Config.vadFrameDuration) {
        self.targetSampleRate = targetSampleRate
        self.frameDuration = frameDuration
        self.samplesPerFrame = Int(Double(targetSampleRate) * frameDuration)
    }
    
    func convertToInt16PCM(from floatBuffer: [Float]) -> [Int16] {
        return floatBuffer.map { sample in
            let scaled = sample * Float(Int16.max)
            let clamped = max(Float(Int16.min), min(Float(Int16.max), scaled))
            return Int16(clamped)
        }
    }
    
    func splitIntoFrames(_ pcmData: [Int16]) -> [[Int16]] {
        var frames: [[Int16]] = []
        var currentIndex = 0
        
        while currentIndex + samplesPerFrame <= pcmData.count {
            let frame = Array(pcmData[currentIndex..<currentIndex + samplesPerFrame])
            frames.append(frame)
            currentIndex += samplesPerFrame
        }
        
        return frames
    }
    
    func processAudioBuffer(_ floatBuffer: [Float]) -> (frames: [[Int16]], originalAudio: [Float]) {
        let int16Buffer = convertToInt16PCM(from: floatBuffer)
        let frames = splitIntoFrames(int16Buffer)
        
        return (frames: frames, originalAudio: floatBuffer)
    }
    
    func frameDataToData(_ frame: [Int16]) -> Data {
        return frame.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }
}