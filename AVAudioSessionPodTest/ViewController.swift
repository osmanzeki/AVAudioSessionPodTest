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
    var samplePlayer: AVAudioPlayer?
    
    // recorder
    var recorder: AVAudioRecorder?
    var recordingPlayer: AVAudioPlayer?
    
    // recording input tap
    // size of the buffer & waveform points
    let bSize: UInt32 = 1024
    // recording buffer
    var rec_engine: AVAudioEngine?
    // recording waveforms per channel
    var waveforms: [[Float32]] = [[]]
    
    var mpVolumeView: MPVolumeView?
    
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
            
            self.addChild(vc)
            vc.didMove(toParent: self)
            

            let safeMargin:CGFloat = UIDevice().hasNotch ? 40.0 : 20.0
            vc.view.frame = CGRect(x: 0, y: safeMargin, width: view.frame.width, height: view.frame.height - safeMargin)

            self.view.addSubview(vc.view)
            
            
            self.mpVolumeView = MPVolumeView(frame: CGRect(x: 0, y: safeMargin, width: vc.view.frame.width, height: vc.view.frame.height - safeMargin))
            self.mpVolumeView?.showsRouteButton = true
            self.mpVolumeView?.showsVolumeSlider = false
            self.mpVolumeView?.isHidden = true
            
            vc.view.addSubview(self.mpVolumeView!)
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
                        
                        // input waveforms
                        for waveform in self.waveforms
                        {
                            imgui.plotLines("", values: waveform, valuesOffset: 0, overlayText: "", scaleMin: -1.0, scaleMax: 1.0)
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
    }
    
    @objc func routeChanged(_ notification: Notification)
    {
        guard
            let _ = notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription
            , let reasonRawValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            , let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRawValue)
            else {
                return
        }
        
        // reflect ports change
        
        // work around .playback category reporting available inputs ( connect in AVAudioEngine then fails.. )
        // in general check input and output node for categories for which they make sense
        switch self.categories[self.categoryIdx]
        {
        // no outputs
        case .record:
            self.availableInputs = AVAudioSession.sharedInstance().availableInputs ?? []
            self.availableOutputs = []
        // no inputs
        case .playback, .ambient, .soloAmbient:
            self.availableInputs = []
            self.availableOutputs = AVAudioSession.sharedInstance().currentRoute.outputs
        default:
            self.availableInputs = AVAudioSession.sharedInstance().availableInputs ?? []
            self.availableOutputs = AVAudioSession.sharedInstance().currentRoute.outputs
        }
        
        // toggle preferred intput change
        // (user's choice (self.preferredInput) should not be changed here - it'd retrigger notification on first input change - which happens .. for reasons (?)
        // input will be found via portName instead again)
        // self.preferredInput = self.availableInputs.first
        
        print("")
        print("===================== route change, reason: \(AudioSessionReasonDescription(reason))")
        print("")
        print("===================== inputs : \(self.availableInputs.count):")
        print("\(self.availableInputs)")
        print("")
        print("===================== outputs: \(self.availableOutputs.count):")
        print("\(self.availableOutputs)")
        print("")
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
        
        
        
        // setup input buffer tap
        self.rec_engine = AVAudioEngine.init()
        
        if let rec_mixer = self.rec_engine?.mainMixerNode, let rec_input = self.rec_engine?.inputNode
        {
            print("Input : \(rec_input.inputFormat(forBus: 0))")
            print("Input : \(rec_input.outputFormat(forBus: 0))")
            print("Output: \(rec_mixer.inputFormat(forBus: 0))")
            print("Output: \(rec_mixer.outputFormat(forBus: 0))")
            
            self.rec_engine?.connect(rec_input, to: rec_mixer, format: rec_input.inputFormat(forBus: 0))
            
            // install the tap
            rec_input.installTap(onBus: 0, bufferSize: self.bSize, format: rec_input.inputFormat(forBus: 0)) { (tapBuffer, when) in
                
                let bufferList = tapBuffer.audioBufferList
                var startBuffer = bufferList.pointee.mBuffers
                let bufferCount = Int(bufferList.pointee.mNumberBuffers)
                
                let buffers = UnsafeBufferPointer<AudioBuffer>(start: &startBuffer, count: bufferCount)
                
                // init result buffers
                if bufferCount != self.waveforms.count
                {
                    self.waveforms = Array(repeating: Array(repeating: 0, count: 0), count: bufferCount)
                }
                
                for i in 0 ..< bufferCount
                {
                    let buffer = buffers[i]
                    let float32Ptr = buffer.mData?.bindMemory(to: Float32.self, capacity: Int(buffer.mDataByteSize))
                    
                    let dataCount = Int(buffer.mDataByteSize) / MemoryLayout<Float32>.size
                    let float32Buffer = UnsafeBufferPointer(start: float32Ptr, count: dataCount)
                    
                    self.waveforms[i] = Array(float32Buffer)
                }
            }

            // start the engine
            self.rec_engine?.prepare()
            try? self.rec_engine?.start()
        }
    }
    
    func StopRecording()
    {
        self.rec_engine?.stop()
        
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
