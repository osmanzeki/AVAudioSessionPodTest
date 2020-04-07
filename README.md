# AVAudioSessionPodTest

# Installation

Install Carthage for Swift. You can chose any method you like, I chose to install it using `brew` for convenience.

```
https://github.com/Carthage/Carthage#installing-carthage
```

At the root of this project directory, in your Terminal app run the following command:

```shell
carthage update
```

This will fetch and compile the ImGui library that was used to build the user interface of the app.

You can now open the project in XCode, change your Signing settings to use your own iOS Developper keys and build on your own devices.

# Instructions (original from base repo)

Base test for recording categories of AVAudioSession, allows all BT options, should handle overrides and route changes correctly

All available inputs and outputs are displayed, user can choose from which available input to record
Works with AirPods™.

Uses [Swift-imgui](https://github.com/mnmly/Swift-imgui) (cause why would you need anyting else ?)

(tested on iOS 12, deployment target prob. iOS 10)

# Installation
Might need carthage bootstrap to set things up correctly

Otherwise just run, preferably with other than default microphone available

# Running
Set your options and mode if needed and press 'Set Category' ( defaults are automatically applied on start )

'Play testing sample' uses its own player to play sample clip on current output

'Start recording' records to temporary file from selected input and plays it looped back immediately once stopped

![AVAudioSessionPodTest](https://raw.githubusercontent.com/osmanzeki/AVAudioSessionPodTest/master/IMG_0272.png)
