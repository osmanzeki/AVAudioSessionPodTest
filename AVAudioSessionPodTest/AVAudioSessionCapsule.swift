//
//  AVAudioSessionCapsule.swift
//  AVAudioSessionPodTest
//
//  Created by r618 on 30/03/2019.
//  Copyright © 2019 r618. All rights reserved.
//
// Wrapper for AVAudioSession

import Foundation
import AVFoundation
import MediaPlayer

class AVAudioSessionCapsule: NSObject
{
    static let sharedInstance = AVAudioSessionCapsule()
    
    // currently running session settings
    var category: AVAudioSession.Category = .playAndRecord
    var mode: AVAudioSession.Mode = .default
    var options: AVAudioSession.CategoryOptions = []
    // all available category inputs
    // first one is default
    // ( can't be queried continuosly (triggers route changes notifications) - saved here on activation / route change )
    var availableInputs: [AVAudioSessionPortDescription] = []
    // all category outputs
    // first one is default
    // ( can't be queried continuosly (triggers route changes notifications) - saved here on activation / route change )
    // overriden via AVAudioSession.PortOverride
    var availableOutputs: [AVAudioSessionPortDescription] = []
    // input override
    var preferredInput: AVAudioSessionPortDescription? = nil

    // recording input tap
    // size of the buffer & waveform points
    let bSize: UInt32 = 1024
    // recording buffer
    var rec_engine: AVAudioEngine?
    // recording waveforms per channel
    var waveforms: [[Float32]] = [[]]
    
    // future : display popover for output selection
    var mpVolumeView: MPVolumeView?
    

    override init() {
        super.init()
    }
    
    func initWithView(_ view:UIView)
    {
        self.mpVolumeView = MPVolumeView(frame: view.frame)
        
        self.mpVolumeView?.showsRouteButton = true
        self.mpVolumeView?.showsVolumeSlider = false
        self.mpVolumeView?.isHidden = true
        
        view.addSubview(self.mpVolumeView!)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func SetupAVAudioSession(_category: AVAudioSession.Category, _mode: AVAudioSession.Mode, _options: AVAudioSession.CategoryOptions)
    {
        // remove notification
        NotificationCenter.default.removeObserver(self)
        
        // deactivate session first
        try? AVAudioSession.sharedInstance().setActive(false, options: AVAudioSession.SetActiveOptions.notifyOthersOnDeactivation)
        
        // set (new) category
        try? AVAudioSession.sharedInstance().setCategory(_category, mode: _mode, options: _options)
        
        self.category = _category
        self.mode = _mode
        self.options = _options
        
        // subscribe to route change notification
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(routeChanged(_:)),
                                               name: AVAudioSession.routeChangeNotification,
                                               object: nil)
        
        // activate session with parameters
        try? AVAudioSession.sharedInstance().setActive(true, options: AVAudioSession.SetActiveOptions.notifyOthersOnDeactivation)
        
        
        // invoke preffered input after category activation to correctly tie input/output (to e.g. iPhone microphone/Receiver) - otherwise with e.g. connected BT device
        // output will stay on BT and setup recording session will not start due to immediate route change with newDeviceAvailable reason
        self.SetPreferredInput(AVAudioSession.sharedInstance().availableInputs?.first)
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
        
        // trigger another route change by querying conected input if there's device change such as dis/connecting BT device
        
        if reason == AVAudioSession.RouteChangeReason.newDeviceAvailable
            || reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable
        {
            // TODO: better this by finding if old preferred device is still present and trigger that instead (new) first one
            self.SetPreferredInput(AVAudioSession.sharedInstance().availableInputs?.first)
        }
        
        // work around .playback category reporting available inputs ( connect in AVAudioEngine then fails.. )
        // in general check input and output node for categories for which they make sense
        switch self.category
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
    
    func SetPreferredInput(_ input:AVAudioSessionPortDescription?)
    {
        try? AVAudioSession.sharedInstance().setPreferredInput(input)
        self.preferredInput = input
    }
    
    func StartRecording()
    {
        self.StopRecording()
        
        // setup input buffer tap
        self.rec_engine = AVAudioEngine.init()
        
        if let rec_mixer = self.rec_engine?.mainMixerNode, let rec_input = self.rec_engine?.inputNode
        {
            print("Input Node In  : \(rec_input.inputFormat(forBus: 0))")
            print("Input Node Out : \(rec_input.outputFormat(forBus: 0))")
            print("Output Node In : \(rec_mixer.inputFormat(forBus: 0))")
            print("Output Node Out: \(rec_mixer.outputFormat(forBus: 0))")
            
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
            
            // without this call after the engine has started, the recorder will record from (for some reason) automatically triggered route change with newDeviceAvailable where e.g. AirPods are default input
            // despite previous setPreferredInput call by user which requested default mic
            // this ensures that preferred input switches back immediately and it seems to work
            // it might be a bug in iOS 12 (.1.4 at the time) - esp. since other bugreports seemed to be submitted - e.g. https://github.com/CraigLn/ios12-airpods-routing-bugreport - dealing with similar inconsistency on outputs -
            // inputs and outpus are tighly coupled for BT devices: see e.g. https://developer.apple.com/library/archive/qa/qa1799/_index.html
            if (self.preferredInput != nil) {
                self.SetPreferredInput(self.preferredInput!)
            }
        }
    }
    
    func StopRecording()
    {
        self.rec_engine?.stop()
    }
}
