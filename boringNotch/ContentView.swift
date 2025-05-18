//
//  ContentView.swift
//  boringNotchApp
//
//  Created by Harsh Vardhan Goswami  on 02/08/24
//  Modified by Richard Kunkli on 24/08/2024.
//

import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import SwiftUI
import SwiftUIIntrospect
import Speech

struct ContentView: View {
    @EnvironmentObject var vm: BoringViewModel
    @StateObject var webcamManager: WebcamManager = .init()

    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared

    @State private var isHovering: Bool = false
    @State private var hoverWorkItem: DispatchWorkItem?
    @State private var debounceWorkItem: DispatchWorkItem?
    
    @State private var isHoverStateChanging: Bool = false

    @State private var gestureProgress: CGFloat = .zero

    @State private var haptics: Bool = false

    @Namespace var albumArtNamespace

    @Default(.useMusicVisualizer) var useMusicVisualizer

    @Default(.showNotHumanFace) var showNotHumanFace
    @Default(.useModernCloseAnimation) var useModernCloseAnimation

    private let extendedHoverPadding: CGFloat = 30
    private let zeroHeightHoverPadding: CGFloat = 10

    var body: some View {
        ZStack(alignment: .top) {
            NotchLayout()
                .frame(alignment: .top)
                .padding(.horizontal, vm.notchState == .open ? Defaults[.cornerRadiusScaling] ? (cornerRadiusInsets.opened - 5) : (cornerRadiusInsets.closed - 5) : 12)
                .padding([.horizontal, .bottom], vm.notchState == .open ? 12 : 0)
                .background(.black)
                .mask {
                    NotchShape(cornerRadius: ((vm.notchState == .open) && Defaults[.cornerRadiusScaling]) ? cornerRadiusInsets.opened : cornerRadiusInsets.closed).drawingGroup()
                }
                .padding(.bottom, vm.notchState == .open && Defaults[.extendHoverArea] ? 0 : (vm.effectiveClosedNotchHeight == 0) ? zeroHeightHoverPadding : 0)

                .conditionalModifier(!useModernCloseAnimation) { view in
                    let hoverAnimationAnimation = Animation.bouncy.speed(1.2)
                    let notchStateAnimation = Animation.spring.speed(1.2)
                        return view
                            .animation(hoverAnimationAnimation, value: isHovering)
                            .animation(notchStateAnimation, value: vm.notchState)
                            .animation(.smooth, value: gestureProgress)
                            .transition(.blurReplace.animation(.interactiveSpring(dampingFraction: 1.2)))
                        }
                .conditionalModifier(useModernCloseAnimation) { view in
                    let hoverAnimationAnimation = Animation.bouncy.speed(1.2)
                    let notchStateAnimation = Animation.spring.speed(1.2)
                    return view
                        .animation(hoverAnimationAnimation, value: isHovering)
                        .animation(notchStateAnimation, value: vm.notchState)
                }
                .conditionalModifier(Defaults[.openNotchOnHover]) { view in
                    view.onHover { hovering in
                        handleHover(hovering)
                    }
                }
                .conditionalModifier(!Defaults[.openNotchOnHover]) { view in
                    view
                        .onHover { hovering in
                            withAnimation(vm.animation) {
                                isHovering = hovering
                            }
                            
                            // Only close if mouse leaves and the notch is open
                            if !hovering && vm.notchState == .open {
                                vm.close()
                            }
                        }
                        .onTapGesture {
                            if (vm.notchState == .closed) && Defaults[.enableHaptics] {
                                haptics.toggle()
                            }
                            doOpen()
                        }
                        .conditionalModifier(Defaults[.enableGestures]) { view in
                            view
                                .panGesture(direction: .down) { translation, phase in
                                    handleDownGesture(translation: translation, phase: phase)
                                }
                        }
                }
                .conditionalModifier(Defaults[.closeGestureEnabled] && Defaults[.enableGestures]) { view in
                    view
                        .panGesture(direction: .up) { translation, phase in
                            handleUpGesture(translation: translation, phase: phase)
                        }
                }
                .onAppear(perform: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        withAnimation(vm.animation) {
                            if coordinator.firstLaunch {
                                doOpen()
                            }
                        }
                    }
                })
                .onChange(of: vm.notchState) { _, newState in
                    // Reset hover state when notch state changes
                    if newState == .closed && isHovering {
                        // Only reset visually, without triggering the hover logic again
                        isHoverStateChanging = true
                        withAnimation {
                            isHovering = false
                        }
                        // Reset the flag after the animation completes
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            isHoverStateChanging = false
                        }
                    }
                }
                .onChange(of: vm.isBatteryPopoverActive) { _, newPopoverState in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if !newPopoverState && !isHovering && vm.notchState == .open {
                            vm.close()
                        }
                    }
                }
                .sensoryFeedback(.alignment, trigger: haptics)
                .contextMenu {
                    SettingsLink(label: {
                        Text("Settings")
                    })
                    .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
//                    Button("Edit") { // Doesnt work....
//                        let dn = DynamicNotch(content: EditPanelView())
//                        dn.toggle()
//                    }
//                    #if DEBUG
//                    .disabled(false)
//                    #else
//                    .disabled(true)
//                    #endif
//                    .keyboardShortcut("E", modifiers: .command)
                }
        }
        .frame(maxWidth: openNotchSize.width, maxHeight: openNotchSize.height, alignment: .top)
        .shadow(color: ((vm.notchState == .open || isHovering) && Defaults[.enableShadow]) ? .black.opacity(0.6) : .clear, radius: Defaults[.cornerRadiusScaling] ? 10 : 5)
        .background(dragDetector)
        .environmentObject(vm)
        .environmentObject(webcamManager)
    }

    @ViewBuilder
      func NotchLayout() -> some View {
          VStack(alignment: .leading) {
              VStack(alignment: .leading) {
                  if coordinator.firstLaunch {
                      Spacer()
                      HelloAnimation().frame(width: 200, height: 80).onAppear(perform: {
                          vm.closeHello()
                      })
                      .padding(.top, 40)
                      Spacer()
                  } else {
                      if coordinator.expandingView.type == .battery && coordinator.expandingView.show && vm.notchState == .closed && Defaults[.showPowerStatusNotifications] {
                        HStack(spacing: 0) {
                            HStack {
                                Text(batteryModel.statusText)
                                    .font(.subheadline)
                            }

                            Rectangle()
                                .fill(.black)
                                .frame(width: vm.closedNotchSize.width + 5)

                            HStack {
                                BoringBatteryView(
                                    batteryWidth: 30,
                                    isCharging: batteryModel.isCharging,
                                    isInLowPowerMode: batteryModel.isInLowPowerMode,
                                    isPluggedIn: batteryModel.isPluggedIn,
                                    levelBattery: batteryModel.levelBattery,
                                    isForNotification: true
                                )
                            }
                            .frame(width: 76, alignment: .trailing)
                        }
                        .frame(height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0), alignment: .center)
                      } else if coordinator.sneakPeek.show && Defaults[.inlineHUD] && (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) {
                          InlineHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon, hoverAnimation: $isHovering, gestureProgress: $gestureProgress)
                              .transition(.opacity)
                      } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .music) && vm.notchState == .closed && (musicManager.isPlaying || !musicManager.isPlayerIdle) && coordinator.musicLiveActivityEnabled && !vm.hideOnClosed {
                          MusicLiveActivity()
                      } else if !coordinator.expandingView.show && vm.notchState == .closed && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace] && !vm.hideOnClosed  {
                          BoringFaceAnimation().animation(.interactiveSpring, value: musicManager.isPlayerIdle)
                      } else if vm.notchState == .open {
                          BoringHeader()
                              .frame(height: max(24, vm.effectiveClosedNotchHeight))
                              .blur(radius: abs(gestureProgress) > 0.3 ? min(abs(gestureProgress), 8) : 0)
                              .animation(.spring(response: 1, dampingFraction: 1, blendDuration: 0.8), value: vm.notchState)
                       } else {
                           Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight)
                       }
                      
                      if coordinator.sneakPeek.show {
                          if (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && !Defaults[.inlineHUD] {
                              SystemEventIndicatorModifier(eventType: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon, sendEventBack: { _ in
                                  //
                              })
                              .padding(.bottom, 10)
                              .padding(.leading, 4)
                              .padding(.trailing, 8)
                          }
                          // Old sneak peek music
                          else if coordinator.sneakPeek.type == .music {
                              if vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard {
                                  HStack(alignment: .center) {
                                      Image(systemName: "music.note")
                                      GeometryReader { geo in
                                          MarqueeText(.constant(musicManager.songTitle + " - " + musicManager.artistName), textColor: .gray, minDuration: 1, frameWidth: geo.size.width)
                                      }
                                  }
                                  .foregroundStyle(.gray)
                                  .padding(.bottom, 10)
                              }
                          }
                      }
                  }
              }
              .conditionalModifier((coordinator.sneakPeek.show && (coordinator.sneakPeek.type == .music) && vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard) || (coordinator.sneakPeek.show && (coordinator.sneakPeek.type != .music) && (vm.notchState == .closed))) { view in
                  view
                      .fixedSize()
              }
              .zIndex(2)
              
              ZStack {
                  if vm.notchState == .open {
                      mainContent
                  }
              }
              .zIndex(1)
              .allowsHitTesting(vm.notchState == .open)
              .blur(radius: abs(gestureProgress) > 0.3 ? min(abs(gestureProgress), 8) : 0)
              .opacity(abs(gestureProgress) > 0.3 ? min(abs(gestureProgress * 2), 0.8) : 1)
          }
      }

    @ViewBuilder
    func BoringFaceAnimation() -> some View {
        HStack {
            HStack {
                Rectangle()
                    .fill(.clear)
                    .frame(width: max(0, vm.effectiveClosedNotchHeight - 12), height: max(0, vm.effectiveClosedNotchHeight - 12))
                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width - 20)
                MinimalFaceFeatures()
            }
        }.frame(height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0), alignment: .center)
    }

    @ViewBuilder
    func MusicLiveActivity() -> some View {
        HStack {
            HStack {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .background(
                        Image(nsImage: musicManager.albumArt)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    )
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed))
                    .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                    .frame(width: max(0, vm.effectiveClosedNotchHeight - 12), height: max(0, vm.effectiveClosedNotchHeight - 12))
            }
            .frame(width: max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12) + gestureProgress / 2), height: max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12)))

            Rectangle()
                .fill(.black)
                .overlay(
                    HStack(alignment: .top){
                        if(coordinator.expandingView.show && coordinator.expandingView.type == .music) {
                            MarqueeText(
                                .constant(musicManager.songTitle),
                                textColor: Defaults[.coloredSpectrogram] ? Color(nsColor: musicManager.avgColor) : Color.gray,
                                minDuration: 0.4,
                                frameWidth: 100
                            )
                            .opacity((coordinator.expandingView.show && Defaults[.enableSneakPeek] && Defaults[.sneakPeekStyles] == .inline) ? 1 : 0)
                            Spacer(minLength: vm.closedNotchSize.width)
                            // Song Artist
                            Text(musicManager.artistName)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(Defaults[.coloredSpectrogram] ? Color(nsColor: musicManager.avgColor) : Color.gray)
                                .opacity((coordinator.expandingView.show && coordinator.expandingView.type == .music && Defaults[.enableSneakPeek] && Defaults[.sneakPeekStyles] == .inline) ? 1 : 0)
                        }
                    }
                )
                .frame(width: (coordinator.expandingView.show && coordinator.expandingView.type == .music && Defaults[.enableSneakPeek] && Defaults[.sneakPeekStyles] == .inline) ? 380 : vm.closedNotchSize.width + (isHovering ? 8 : 0))
            

            HStack {
                if useMusicVisualizer {
                    Rectangle()
                        .fill(Defaults[.coloredSpectrogram] ? Color(nsColor: musicManager.avgColor).gradient : Color.gray.gradient)
                        .frame(width: 50, alignment: .center)
                        .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
                        .mask {
                            AudioSpectrumView(isPlaying: $musicManager.isPlaying)
                                .frame(width: 16, height: 12)
                        }
                        .frame(width: max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12) + gestureProgress / 2),
                               height: max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12)), alignment: .center)
                } else {
                    LottieAnimationView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12) + gestureProgress / 2),
                   height: max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12)), alignment: .center)
        }
        .frame(height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0), alignment: .center)
    }

    @ViewBuilder
    var dragDetector: some View {
        if Defaults[.boringShelf] {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onDrop(of: [.data], isTargeted: $vm.dragDetectorTargeting) { _ in true }
                .onChange(of: vm.anyDropZoneTargeting) { _, isTargeted in
                    if isTargeted, vm.notchState == .closed {
                        coordinator.currentView = .shelf
                        doOpen()
                    } else if !isTargeted {
                        print("DROP EVENT", vm.dropEvent)
                        if vm.dropEvent {
                            vm.dropEvent = false
                            return
                        }

                        vm.dropEvent = false
                        vm.close()
                    }
                }
        } else {
            EmptyView()
        }
    }

    private func doOpen() {
        withAnimation(.bouncy.speed(1.2)) {
            vm.open()
        }
    }

    // MARK: - Hover Management
    
    /// Handle hover state changes with debouncing
    private func handleHover(_ hovering: Bool) {
        // Don't process events if we're already transitioning
        if isHoverStateChanging { return }
        
        // Cancel any pending tasks
        hoverWorkItem?.cancel()
        hoverWorkItem = nil
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        
        if hovering {
            // Handle mouse enter
            withAnimation(.bouncy.speed(1.2)) {
                isHovering = true
            }
            
            // Only provide haptic feedback if notch is closed
            if vm.notchState == .closed && Defaults[.enableHaptics] {
                haptics.toggle()
            }
            
            // Don't open notch if there's a sneak peek showing
            if coordinator.sneakPeek.show {
                return
            }
            
            // Delay opening the notch
            let task = DispatchWorkItem {
                // ContentView is a struct, so we don't use weak self here
                guard vm.notchState == .closed, isHovering else { return }
                doOpen()
            }
            
            hoverWorkItem = task
            DispatchQueue.main.asyncAfter(
                deadline: .now() + Defaults[.minimumHoverDuration],
                execute: task
            )
        } else {
            // Handle mouse exit with debounce to prevent flickering
            let debounce = DispatchWorkItem {
                // ContentView is a struct, so we don't use weak self here
                
                // Update visual state
                withAnimation(.bouncy.speed(1.2)) {
                    isHovering = false
                }
                
                // Close the notch if it's open and battery popover is not active
                if vm.notchState == .open && !vm.isBatteryPopoverActive {
                    vm.close()
                }
            }
            
            debounceWorkItem = debounce
            // Add a small delay to debounce rapid mouse movements
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: debounce)
        }
    }
    
    // MARK: - Gesture Handling
    
    private func handleDownGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .closed else { return }
        
        withAnimation(.smooth) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * 20
        }
        
        if phase == .ended {
            withAnimation(.smooth) {
                gestureProgress = .zero
            }
        }
        
        if translation > Defaults[.gestureSensitivity] {
            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
            withAnimation(.smooth) {
                gestureProgress = .zero
            }
            doOpen()
        }
    }
    
    private func handleUpGesture(translation: CGFloat, phase: NSEvent.Phase) {
        if vm.notchState == .open && !vm.isHoveringCalendar {
            withAnimation(.smooth) {
                gestureProgress = (translation / Defaults[.gestureSensitivity]) * -20
            }
            
            if phase == .ended {
                withAnimation(.smooth) {
                    gestureProgress = .zero
                }
            }
            
            if translation > Defaults[.gestureSensitivity] {
                withAnimation(.smooth) {
                    gestureProgress = .zero
                    isHovering = false
                }
                vm.close()
                
                if Defaults[.enableHaptics] {
                    haptics.toggle()
                }
            }
        }
    }

    private var mainContent: some View {
        HStack(alignment: .top, spacing: 20) {
            switch coordinator.currentView {
            case .home:
                MusicPlayerView(albumArtNamespace: albumArtNamespace)
                if Defaults[.showCalendar] {
                    CalendarView()
                        .onHover { isHovering in
                            vm.isHoveringCalendar = isHovering
                        }
                        .environmentObject(vm)
                }
                if Defaults[.showMirror] && webcamManager.cameraAvailable {
                    CameraPreviewView(webcamManager: webcamManager)
                        .scaledToFit()
                        .opacity(vm.notchState == .closed ? 0 : 1)
                        .blur(radius: vm.notchState == .closed ? 20 : 0)
                }
            case .shelf:
                NotchShelfView()
            case .voice:
                VoiceAssistantView()
            }
        }
        .transition(.opacity.animation(.smooth.speed(0.9))
            .combined(with: .blurReplace.animation(.smooth.speed(0.9)))
            .combined(with: .move(edge: .top)))
        .blur(radius: vm.notchState == .closed ? 30 : 0)
    }
}

struct FullScreenDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onDrop: () -> Void

    func dropEntered(info _: DropInfo) {
        isTargeted = true
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func performDrop(info _: DropInfo) -> Bool {
        isTargeted = false
        onDrop()
        return true
    }
}

struct VoiceAssistantView: View {
    @State private var isRecording = false
    @State private var response: String? = nil
    @State private var isProcessing = false
    @State private var recordingTimer: Timer? = nil
    @State private var commandOutput: String = ""
    @State private var commandError: String? = nil
    @State private var debugLog: String = "Debug log will appear here"
    @State private var transcribedText: String = ""
    @State private var goosePath: String = "/usr/local/bin/goose"
    @State private var manualCommand: String = ""
    @State private var mcpInitialized: Bool = false
    @State private var speechRecognitionAvailable: Bool = true
    
    // Audio recording properties
    @State private var audioEngine = AVAudioEngine()
    @State private var recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var recognitionTask: SFSpeechRecognitionTask?

    var body: some View {
        VStack {
            Text("Goose AI Assistant")
                .font(.headline)
                .padding(.top, 20)
            
            // Debug status
            Text(debugLog)
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.horizontal)
                .multilineTextAlignment(.center)
            
            Spacer()
            Button(action: {
                if !isRecording {
                    startRealRecording()
                } else {
                    stopRealRecording()
                }
            }) {
                ZStack {
                    Circle()
                        .fill(Color.black)
                        .frame(width: 80, height: 80)
                        .shadow(radius: 10)
                    Image(systemName: isRecording ? "mic.fill" : "mic.circle.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 60, height: 60)
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.bottom, 8)
            
            Text(isRecording ? "Listening... Tap to stop" : "Push to talk")
                .font(.headline)
                .foregroundColor(.gray)
            
            if isRecording {
                RecordingIndicator()
                    .padding(.top, 8)
            }
            
            if isProcessing {
                ProgressView("Processing query...")
                    .padding(.top, 16)
            }
            
            if !transcribedText.isEmpty {
                VStack(alignment: .leading) {
                    Text("You said:")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    
                    Text(transcribedText)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 16)
            }
            
            if let error = commandError {
                Text("Error: \(error)")
                    .foregroundColor(.red)
                    .font(.footnote)
                    .padding(.top, 8)
                    .padding(.horizontal)
                    .multilineTextAlignment(.center)
            }
            
            if !commandOutput.isEmpty {
                Text("Goose Response:")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .padding(.top, 8)
                
                ScrollView {
                    Text(commandOutput)
                        .font(.body)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(8)
                        .padding(.horizontal)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxHeight: 250)
                .padding(.horizontal)
            }
            
            // Manual command entry section
            VStack {
                Text("Or type your command:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    TextField("Enter command", text: $manualCommand)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(height: 30)
                    
                    Button(action: {
                        if !manualCommand.isEmpty {
                            transcribedText = manualCommand
                            executeGooseCommand(manualCommand)
                            manualCommand = ""
                        }
                    }) {
                        Text("Send")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(manualCommand.isEmpty)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
            
            Spacer()
            
            HStack(spacing: 20) {
                Button("Run Help") {
                    self.transcribedText = "help"
                    executeGooseCommand("help")
                }
                
                Button("What is Goose?") {
                    self.transcribedText = "what is goose"
                    executeGooseCommand("what is goose")
                }
            }
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onAppear {
            debugLog = "Voice Assistant initialized"
            print("Voice Assistant initialized - checking Goose path")
            checkGoosePath()
            requestSpeechPermission()
        }
        .onChange(of: goosePath) { oldValue, newValue in
            if !newValue.isEmpty && newValue != oldValue {
                // Goose path found, now initialize MCP
                initializeMCP()
            }
        }
    }

    func requestSpeechPermission() {
        // Request speech recognition permission
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                let hasSpeechPermission = (status == .authorized)
                self.updateDebugLog("Speech recognition permission: \(hasSpeechPermission)")
                self.speechRecognitionAvailable = hasSpeechPermission
                
                if !hasSpeechPermission {
                    self.commandError = "Speech recognition not authorized. Please use text input instead."
                }
            }
        }
    }
    
    func startRealRecording() {
        // Ensure the speech recognizer is available
        guard let recognizer = recognizer, recognizer.isAvailable, speechRecognitionAvailable else {
            updateDebugLog("Speech recognizer not available")
            commandError = "Speech recognition not available. Please use text input instead."
            return
        }
        
        // Clean up any existing tasks first
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
            recognitionRequest?.endAudio()
            recognitionTask?.cancel()
            recognitionTask = nil
            recognitionRequest = nil
        }
        
        // Initialize the recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            updateDebugLog("Unable to create speech recognition request")
            return
        }
        
        // Configure for continuous recognition
        recognitionRequest.shouldReportPartialResults = true
        
        // Create and configure the audio engine
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Install a tap on the input node
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        // Start the audio engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
            transcribedText = ""
            updateDebugLog("Started voice recording")
            
            // Start speech recognition
            recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { result, error in
                var isFinal = false
                
                if let result = result {
                    // Update the transcribed text with the latest recognition result
                    self.transcribedText = result.bestTranscription.formattedString
                    isFinal = result.isFinal
                }
                
                if error != nil || isFinal {
                    // Stop recording if there's an error or the recognition is final
                    self.audioEngine.stop()
                    inputNode.removeTap(onBus: 0)
                    
                    if let error = error {
                        let errorString = error.localizedDescription
                        self.updateDebugLog("Recognition error: \(errorString)")
                        
                        // Handle specific AFAssistantErrorDomain error
                        if errorString.contains("AFAssistantErrorDomain") && errorString.contains("1101") {
                            self.speechRecognitionAvailable = false
                            self.commandError = "Speech recognition service unavailable. Please use text input."
                        }
                        
                        self.stopRealRecording()
                    } else if isFinal {
                        self.stopRealRecording()
                    }
                    
                    self.recognitionRequest = nil
                    self.recognitionTask = nil
                }
            }
        } catch {
            updateDebugLog("Failed to start recording: \(error)")
            stopRealRecording()
        }
    }
    
    func stopRealRecording() {
        // Make sure we're actually recording
        if !isRecording {
            return
        }
        
        // Stop the audio engine
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        // End the recognition request
        recognitionRequest?.endAudio()
        
        // Clean up
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        
        isRecording = false
        isProcessing = true
        updateDebugLog("Stopped recording, processing: '\(transcribedText)'")
        
        // Process the transcribed text
        if !transcribedText.isEmpty {
            executeGooseCommand(transcribedText)
        } else {
            isProcessing = false
            updateDebugLog("No speech detected")
        }
    }

    func checkGoosePath() {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.executeShellCommand("which goose")
            DispatchQueue.main.async {
                if let output = result.output, !output.isEmpty {
                    self.goosePath = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.debugLog = "Goose found at: \(self.goosePath)"
                    print("Goose found at: \(self.goosePath)")
                    
                    // Initialize MCP immediately after finding Goose
                    self.initializeMCP()
                } else {
                    self.debugLog = "Goose not found on PATH: \(result.error ?? "unknown error")"
                    print("Goose not found on PATH: \(result.error ?? "unknown error")")
                }
            }
        }
    }

    func executeGooseCommand(_ query: String) {
        isProcessing = true
        commandError = nil
        commandOutput = ""
        
        let normalizedQuery = query.replacingOccurrences(of: "'", with: "'\\''") // Escape single quotes
        
        print("Executing Goose command: \(query)")
        debugLog = "Executing Goose command: '\(query)'"
        
        // Use the technique from the article to execute the command
        DispatchQueue.global(qos: .userInitiated).async {
            // Try using the detected goose path
            let command = "echo '\(normalizedQuery)' | \(self.goosePath)"
            print("Executing command: \(command)")
            self.updateDebugLog("Running: \(command)")
            
            let result = self.executeShellCommand(command)
            
            DispatchQueue.main.async {
                self.isProcessing = false
                
                if let error = result.error, !error.isEmpty {
                    print("Error executing Goose: \(error)")
                    self.updateDebugLog("Error executing Goose")
                    self.commandError = "Failed to run Goose: \(error)"
                } else if let output = result.output {
                    print("Command succeeded with output length: \(output.count)")
                    self.updateDebugLog("Command successful!")
                    
                    // Handle EOF errors in output
                    if output.contains("Error: Session ended with error: EOF") {
                        self.commandOutput = "The AI session timed out or was disconnected. Please try again."
                    } else {
                        self.commandOutput = self.formatGooseOutput(output)
                    }
                } else {
                    print("No output received")
                    self.updateDebugLog("No output received")
                    self.commandError = "No output received from Goose"
                }
            }
        }
    }
    
    func updateDebugLog(_ message: String) {
        DispatchQueue.main.async {
            self.debugLog = message
            print("DEBUG: \(message)")
        }
    }
    
    func executeShellCommand(_ command: String) -> (output: String?, error: String?) {
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-l", "-c", command]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        
        do {
            try task.run()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            let output = String(data: outputData, encoding: .utf8)
            let error = String(data: errorData, encoding: .utf8)
            
            print("Raw command output length: \(outputData.count) bytes")
            if let output = output, !output.isEmpty {
                print("Output: \(output.prefix(100))...")
            }
            if let error = error, !error.isEmpty {
                print("Error: \(error)")
            }
            
            task.waitUntilExit()
            
            if task.terminationStatus != 0 {
                print("Process exited with code: \(task.terminationStatus)")
                return (nil, error ?? "Process exited with code \(task.terminationStatus)")
            }
            
            return (output, nil)
        } catch {
            print("Failed to run process: \(error.localizedDescription)")
            return (nil, error.localizedDescription)
        }
    }

    // Format Goose CLI output to extract just the AI response
    func formatGooseOutput(_ output: String) -> String {
        // Split the output into lines
        let lines = output.components(separatedBy: .newlines)
        
        // Filter out log lines and extract the actual AI response
        var processingResponse = false
        var responseLines: [String] = []
        
        for line in lines {
            // Skip log lines and headers
            if line.contains("starting session") || 
               line.contains("logging to") ||
               line.contains("working directory:") ||
               line.contains("Error: Session ended") {
                continue
            }
            
            // Skip prompt display line
            if line.contains("Goose is running!") {
                processingResponse = true
                continue
            }
            
            // Stop at the next prompt
            if line.starts(with: "( O)>") {
                if responseLines.isEmpty {
                    processingResponse = true
                    continue
                } else {
                    break
                }
            }
            
            // Capture the response
            if processingResponse {
                responseLines.append(line)
            }
        }
        
        let formattedResponse = responseLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return formattedResponse.isEmpty ? "No response from Goose" : formattedResponse
    }
    
    // Function to run MCP after Goose is found
    func initializeMCP() {
        guard !mcpInitialized else { return } // Only run once
        
        mcpInitialized = true
        debugLog = "Initializing MCP with Goose at: \(goosePath)"
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Run the exact MCP command
            let mcpCommand = "npx -y @smithery/cli@latest run @browserbasehq/mcp-stagehand --profile sheer-chameleon-SI8B6T --key d2527900-4821-408a-b2c2-088f9f454921"
            let result = self.executeShellCommand(mcpCommand)
            
            DispatchQueue.main.async {
                if let error = result.error, !error.isEmpty {
                    self.debugLog = "MCP initialization error: \(error)"
                    print("MCP initialization error: \(error)")
                } else if let output = result.output {
                    self.debugLog = "MCP initialized successfully"
                    print("MCP initialized with output: \(output)")
                }
            }
        }
    }
}

struct RecordingIndicator: View {
    @State private var animate = false
    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 14, height: 14)
            .scaleEffect(animate ? 1.2 : 0.8)
            .opacity(animate ? 0.7 : 1)
            .animation(Animation.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: animate)
            .onAppear { animate = true }
    }
}

#Preview {
    VoiceAssistantView()
}
