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

class ViewController: UIViewController
{
    // only .playAndRecord .record categories makes sense since we want to test recording
    // (.playAndRecord supports only mirrored variant of AirPlay, which seems to be the only difference to playback modes/categories)
    // https://developer.apple.com/documentation/avfoundation/avaudiosession/audio_session_categories?language=objc
    var categories: [AVAudioSession.Category] = [.record, .playAndRecord]
    var categoryIdx: Int = 1
    // mode selected
    var mode: AVAudioSession.Mode = AVAudioSession.Mode.default
    // modes for category -  we select only handful which make sense for recording
    let modeList: [AVAudioSession.Mode] = [.default, .voiceChat, .videoChat, .gameChat, .videoRecording, .spokenAudio]
    // options selected
    var options: AVAudioSession.CategoryOptions = []
    // options subset - we select only handful which make sense for recording
    let optionsList: AVAudioSession.CategoryOptions = [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
    // all available category inputs
    // first one is default
    // ( can't be queried continuosly (triggers route changes notifications) - saved here on activation / route change )
    var availableInputs: [AVAudioSessionPortDescription] = []
    // input override
    var preferredInput: AVAudioSessionPortDescription? = nil
    // all category outputs
    // first one is default
    // ( can't be queried continuosly (triggers route changes notifications) - saved here on activation / route change )
    // overriden via AVAudioSession.PortOverride
    var availableOutputs: [AVAudioSessionPortDescription] = []

    
    // sample clip player for testing output
    var samplePlayer: AVAudioPlayer?;
    
    // recorder
    var recorder: AVAudioRecorder?;
    var recordingPlayer: AVAudioPlayer?;
    
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
        self.SetupAudioSession()
        
        // start ImGui
        ImGui.initialize(ImGui.API.metal)
        
        // Add ImGui viewController and view to scene
        if let vc = ImGui.vc {
            
            addChild(vc)
            vc.didMove(toParent: self)
            
            view.addSubview(vc.view)
            
            let safeMargin:CGFloat = UIDevice().hasNotch ? 40.0 : 20.0
            vc.view.frame = CGRect(x: 0, y: safeMargin, width: view.frame.width, height: view.frame.height - safeMargin)
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
                self.SetupAudioSession()
            }
            imgui.text("....................")
            
            
            imgui.text("Category inputs: ")
            for input in self.availableInputs
            {
                if imgui.radioButton(input.portName, active: self.preferredInput?.portName == input.portName)
                {
                    self.preferredInput = input
                    try? AVAudioSession.sharedInstance().setPreferredInput(self.preferredInput)
                }
            }
            
            imgui.text("Category outputs: ")
            for output in self.availableOutputs
            {
                imgui.text(output.portName)
            }
            
            
            
            if self.availableOutputs.count > 0
            {
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
            
            if recordingAllowed && self.availableInputs.count > 0
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
                    if self.recorder?.isRecording ?? false
                    {
                        if imgui.button("Stop recording")
                        {
                            self.StopRecording()
                            self.StartRecordingPlayback()
                        }
                    }
                    else
                    {
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
    
    func SetupAudioSession()
    {
        self.samplePlayer?.stop()
        
        // deactivate session first:
        NotificationCenter.default.removeObserver(self)
        
        try? AVAudioSession.sharedInstance().setActive(false, options: AVAudioSession.SetActiveOptions.notifyOthersOnDeactivation)
        
        NotificationCenter.default.removeObserver(self)
        
        // set (new) category
        try? AVAudioSession.sharedInstance().setCategory(self.categories[self.categoryIdx], mode: self.mode, options: self.options)
        // subscibe to route change notification
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(routeChanged(_:)),
                                               name: AVAudioSession.routeChangeNotification,
                                               object: nil)

        // activate session with entered parameters
        try? AVAudioSession.sharedInstance().setActive(true, options: AVAudioSession.SetActiveOptions.notifyOthersOnDeactivation)

        // grab inputs and outputs
        // AVAudioSession.sharedInstance().availableInputs?.map{ print($0.portName) }
        self.availableInputs = AVAudioSession.sharedInstance().availableInputs ?? []
        self.availableOutputs = AVAudioSession.sharedInstance().currentRoute.outputs
        
        
        // toggle preferred intput change
        self.preferredInput = self.availableInputs.first
        try? AVAudioSession.sharedInstance().setPreferredInput(self.preferredInput)
    }
    
    @objc func routeChanged(_ notification: Notification)
    {
        guard let _ = notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription,
            let reasonRawValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRawValue) else {
                return
        }
        
        print("")
        print("===================== route change - \(reason)")
        print("")
        
        // reflect ports change
        // (user's choice (self.preferredInput) should not be changed here - it'd retrigger notification on first input change - which happens .. for reasons (?)
        // input will be found vie portName instead again)
        self.availableInputs = AVAudioSession.sharedInstance().availableInputs ?? []
        self.availableOutputs = AVAudioSession.sharedInstance().currentRoute.outputs
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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
        let audioFilename = getDocumentsDirectory().appendingPathComponent("recording.m4a")
        
        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 24000,
            AVNumberOfChannelsKey: 2,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        self.recorder = try? AVAudioRecorder(url: audioFilename, settings: settings)
        self.recorder?.record()
        
        // without this call after the recording has started, the recorder will record from (for some reason) automatically triggered route change where e.g. AirPods are default input
        // despite previous setPreferredInput call by user which requested default mic
        // this ensures that preferred input switches back immediately and it seems to work
        // it might be a bug in iOS 12 (.1.4 at the time) - esp. since other bugreports seemed to be submitted - e.g. https://github.com/CraigLn/ios12-airpods-routing-bugreport - dealing with similar inconsistency on outputs -
        // inputs and outpus are tighly coupled for BT devices: see e.g. https://developer.apple.com/library/archive/qa/qa1799/_index.html
        try? AVAudioSession.sharedInstance().setPreferredInput(self.preferredInput)
    }
    
    func StopRecording()
    {
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
