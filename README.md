# AVAudioSessionPodTest

Base test for recording categories of AVAudioSession, allows all BT options, should handle overrides and route changes correctly

All available inputs and outputs are displayed, user can choose from which available input to record
Works with AirPods™.

Uses [Swift-imgui](https://github.com/mnmly/Swift-imgui) (cause why would you need anyting else ?)

# Installation
Might need carthage bootstrap to set things up correctly

Otherwise just run, preferably with other than default microphone available

# Running
Set your options and mode if needed and press 'Set Category' ( defaults are automatically applied on start )

'Play testing sample' uses its own player to play sample clip on current output

'Start recording' records to temporary file from selected input and plays it looped back immediately once stopped
