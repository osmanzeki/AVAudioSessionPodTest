//
//  ViewController.swift
//  AVAudioSessionPodTest
//
//  Created by r618 on 24/02/2019.
//  Copyright © 2019 Martin Cvengroš. All rights reserved.
//

import UIKit
import ImGui
import AVFoundation
import MediaPlayer

class ViewController: UIViewController
{
    // only .playAndRecord .record categories makes sense since we want to test recording
    // (.playAndRecord supports only mirrored variant of AirPlay, which seems to be the only difference to playback modes/categories)
    // https://developer.apple.com/documentation/avfoundation/avaudiosession/audio_session_categories?language=objc
    var categories: [AVAudioSession.Category] = [.record, .playAndRecord, .playback, .ambient, .soloAmbient, .multiRoute]
    var categoryIdx: Int = 1
    // mode selected
    var mode: AVAudioSession.Mode = AVAudioSession.Mode.default
    // modes for category -  we select only handful which make sense for recording
    let modeList: [AVAudioSession.Mode] = [.default, .voiceChat, .videoChat, .gameChat, .videoRecording, .spokenAudio]
    // options selected
    var options: AVAudioSession.CategoryOptions = []
    // options subset - we select only handful which make sense for recording
    let optionsList: AVAudioSession.CategoryOptions = [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
    
    // sample clip player for testing output
    var samplePlayer: AVAudioPlayer?
    
    // recorder
    var recordToFile: Bool = true
    var recorder: AVAudioRecorder?
    var recordingPlayer: AVAudioPlayer?
    
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        var recordingAllowed = true
        if AVAudioSession.sharedInstance().recordPermission != AVAudioSession.RecordPermission.granted
        {
            AVAudioSession.sharedInstance().requestRecordPermission() { allowed in
                recordingAllowed = allowed
            }
        }

        // start audio session with defaults
        AVAudioSessionCapsule.sharedInstance.SetupAVAudioSession(_category: self.categories[self.categoryIdx], _mode: self.mode, _options: self.options)
        
        // start ImGui
        ImGui.initialize(ImGui.API.metal)
        
        // Add ImGui viewController and view to scene
        if let vc = ImGui.vc {
            
            self.addChild(vc)
            vc.didMove(toParent: self)
            

            let safeMargin:CGFloat = UIDevice().hasNotch ? 40.0 : 20.0
            vc.view.frame = CGRect(x: 0, y: safeMargin, width: self.view.frame.width, height: self.view.frame.height - safeMargin)

            self.view.addSubview(vc.view)
        }
        
        // do imgui
        ImGui.draw { (imgui) in
            
            // this is the ultimate stupidity, but avoid unbearable flickering of the ImGui which for some reason happens on my iPhone 7
            // less when under debugging session, but the UI is completely unusable when run normally on the phone
            usleep(100)
            
            imgui.setWindowFontScale(2.25)
            
            // create a window overlayed over the whole canvas so we can customize appearance and behaviour
            imgui.setNextWindowPos(CGPoint.zero, cond: .always)
            imgui.setNextWindowSize(self.view.frame.size)
            
            imgui.begin("AVAudioSession recording 🧪_-ªº", show: nil, flags: [ImGuiWindowFlags.noCollapse, ImGuiWindowFlags.noMove, ImGuiWindowFlags.noResize])
            
            // this has to be after the window opening, for some reason
            imgui.setWindowFontScale(2.25)
            
            imgui.text("Press Set Category after changing options")
            
            //
            // category
            // combo - only one active
            imgui.combo("", currentItemIndex: &self.categoryIdx, items: self.categories.map{ $0.rawValue })
            imgui.text(String(format: "Category: %@", self.categories[self.categoryIdx] as CVarArg))
            //
            // mode
            // radio buttons - only one active
            imgui.text("Mode:")
            for m in self.modeList {
                if imgui.radioButton("\(m.rawValue)", active: self.mode == m) { self.mode = m }
            }
            //
            // options
            // checkbox for each option in OptionSet
            imgui.text("Options: ")
            for opt in self.optionsList.elements() {
                
                var checked: Bool = self.options.contains(opt) // mutable for imgui
                
                let label = AudioSessionCategoryOptionDescription(option: opt)
                
                if imgui.checkbox(label, active: &checked) {
                    if checked {
                        self.options.insert(opt)
                    }
                    else {
                        self.options.remove(opt)
                    }
                }
            }
            
            if imgui.button("Set Category of AVAudioSession")
            {
                AVAudioSessionCapsule.sharedInstance.SetupAVAudioSession(_category: self.categories[self.categoryIdx], _mode: self.mode, _options: self.options)
            }
            imgui.text("....................")
            
            
            imgui.text("Category inputs: ")
            for input in AVAudioSessionCapsule.sharedInstance.availableInputs
            {
                if imgui.radioButton(input.portName, active: AVAudioSessionCapsule.sharedInstance.preferredInput?.portName == input.portName)
                {
                    AVAudioSessionCapsule.sharedInstance.SetPreferredInput(input)
                }
            }
            
            imgui.text("Category outputs: ")
            for output in AVAudioSessionCapsule.sharedInstance.availableOutputs
            {
                imgui.text(output.portName)
            }
            
            
            
            if AVAudioSessionCapsule.sharedInstance.availableOutputs.count > 0
            {
//                if imgui.button("Show output selector")
//                {
//                    self.mpVolumeView?.isHidden = false
//                }
                
                if imgui.button("Request Speaker override")
                {
                    try? AVAudioSession.sharedInstance().overrideOutputAudioPort(AVAudioSession.PortOverride.speaker)
                }
                imgui.sameLine()
                if imgui.button("Request default output")
                {
                    try? AVAudioSession.sharedInstance().overrideOutputAudioPort(AVAudioSession.PortOverride.none)
                }
                imgui.text("....................")
            
                let playing = self.samplePlayer?.isPlaying ?? false
                let label = playing ? "Stop playing sample" : "Play testing sample"
                if imgui.button(label)
                {
                    if playing
                    {
                        self.StopSamplePlayer()
                    }
                    else
                    {
                        self.StartSamplePlayer()
                    }
                }
            }
            
            imgui.text("....................")
            
            if recordingAllowed && AVAudioSessionCapsule.sharedInstance.availableInputs.count > 0
            {
                if self.recordingPlayer?.isPlaying ?? false
                {
                    if imgui.button("Stop recording playback")
                    {
                        self.StopRecordingPlayback()
                    }
                }
                else
                {
                    if AVAudioSessionCapsule.sharedInstance.rec_engine?.isRunning ?? false
                        || self.recorder?.isRecording ?? false
                    {
                        if imgui.button("Stop recording")
                        {
                            self.StopRecording()
                            
                            if (self.recordToFile) {
                                self.StartRecordingPlayback()
                            }
                        }
                        
                        // input waveforms
                        for waveform in AVAudioSessionCapsule.sharedInstance.waveforms
                        {
                            imgui.plotLines("", values: waveform, valuesOffset: 0, overlayText: "", scaleMin: -1.0, scaleMax: 1.0)
                        }
                    }
                    else
                    {
                        imgui.checkbox("Record to file", active: &self.recordToFile)
                        
                        if imgui.button("Start recording")
                        {
                            self.StartRecording()
                        }
                    }
                }
            }
            
            imgui.end()
        }
    }
    

    
    
    

    func StartSamplePlayer()
    {
        let fileName = "262447__xinematix__action-percussion-ensemble-fast-4-170-bpm";
        let path = Bundle.main.path(forResource: fileName, ofType:"wav")!
        let url = URL(fileURLWithPath: path)
        
        self.samplePlayer = try? AVAudioPlayer(contentsOf: url)
        self.samplePlayer?.prepareToPlay()
        self.samplePlayer?.volume = 1.0
        self.samplePlayer?.numberOfLoops = -1
        self.samplePlayer?.play()
    }
    
    func StopSamplePlayer()
    {
        self.samplePlayer?.stop()
    }
    
    func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        return documentsDirectory
    }
    
    func StartRecording()
    {
        AVAudioSessionCapsule.sharedInstance.StartRecording()
        
        if self.recordToFile
        {
            let audioFilename = getDocumentsDirectory().appendingPathComponent("recording.m4a")
            
            let settings = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 24000,
                AVNumberOfChannelsKey: 2,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            
            self.recorder = try? AVAudioRecorder(url: audioFilename, settings: settings)
            self.recorder?.record()
        }
    }
    
    func StopRecording()
    {
        AVAudioSessionCapsule.sharedInstance.StopRecording()
        
        self.recorder?.stop()
        self.recorder = nil
    }
    

    func StartRecordingPlayback()
    {
        let audioFilename = getDocumentsDirectory().appendingPathComponent("recording.m4a")
        
        try? self.recordingPlayer = AVAudioPlayer(contentsOf: audioFilename)
        self.recordingPlayer?.prepareToPlay()
        self.recordingPlayer?.volume = 1.0
        self.recordingPlayer?.numberOfLoops = -1
        self.recordingPlayer?.play()
    }
    
    func StopRecordingPlayback()
    {
        self.recordingPlayer?.stop()
        self.recordingPlayer = nil
    }

}
