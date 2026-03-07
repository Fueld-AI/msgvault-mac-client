import Foundation
import Speech
import AVFoundation

@MainActor
final class SpeechInputManager: ObservableObject {
    @Published var isListening = false
    @Published var errorMessage: String?
    
    private let recognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    func toggleListening(onTextUpdate: @escaping (String) -> Void) {
        if isListening {
            stopListening()
        } else {
            startListening(onTextUpdate: onTextUpdate)
        }
    }
    
    func stopListening() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        isListening = false
    }
    
    private func startListening(onTextUpdate: @escaping (String) -> Void) {
        errorMessage = nil
        
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard let self else { return }
            Task { @MainActor in
                switch status {
                case .authorized:
                    do {
                        try self.beginRecognition(onTextUpdate: onTextUpdate)
                    } catch {
                        self.errorMessage = "Voice input failed: \(error.localizedDescription)"
                        self.stopListening()
                    }
                case .denied:
                    self.errorMessage = "Speech recognition permission denied. Enable it in macOS Privacy settings."
                case .restricted:
                    self.errorMessage = "Speech recognition is restricted on this Mac."
                case .notDetermined:
                    self.errorMessage = "Speech recognition permission has not been granted."
                @unknown default:
                    self.errorMessage = "Speech recognition is unavailable."
                }
            }
        }
    }
    
    private func beginRecognition(onTextUpdate: @escaping (String) -> Void) throws {
        guard let recognizer, recognizer.isAvailable else {
            throw NSError(domain: "SpeechInputManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer is unavailable."])
        }
        
        stopListening()
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        isListening = true
        
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            
            if let result {
                onTextUpdate(result.bestTranscription.formattedString)
                if result.isFinal {
                    self.stopListening()
                }
            }
            
            if let error {
                self.errorMessage = "Voice input failed: \(error.localizedDescription)"
                self.stopListening()
            }
        }
    }
}
