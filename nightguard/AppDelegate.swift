//
//  AppDelegate.swift
//  scoutwatch
//
//  Created by Dirk Hermanns on 20.11.15.
//  Copyright © 2015 private. All rights reserved.
//

import UIKit
import MediaPlayer
import WatchConnectivity
import BackgroundTasks

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
   // let appProcessingTaskId = "de.my-wan.dhe.nightguard.background"
    let appProcessingTaskId = "myyan.ayan.nightguardMat.background"
    
    // Delegate Requests from the Watch to the WatchMessageService
    var session: WCSession? {
        didSet {
            if let session = session {
                session.delegate = WatchMessageService.singleton
                session.activate()
            }
        }
    }
    
    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        if CommandLine.arguments.contains("--uitesting") {
            configureAppForTesting()
        }

        // Override point for customization after application launch.
        UITabBar.appearance().tintColor = UIColor.white

        UITextField.appearance().keyboardAppearance = .dark
        
        // set "prevent screen lock" to ON when the app is started for the first time
        if !SharedUserDefaultsRepository.screenlockSwitchState.exists {
            SharedUserDefaultsRepository.screenlockSwitchState.value = true
        }
        
        // set the "prevent screen lock" option when the app is started
        UIApplication.shared.isIdleTimerDisabled = SharedUserDefaultsRepository.screenlockSwitchState.value
        
        AlarmSound.volumeChangeDetector.onVolumeChange = { [weak self] in
            self?.window?.rootViewController?.handleQuickSnooze(option: UserDefaultsRepository.volumeKeysOnAlertSnoozeOption.value)
        }
        
        activateWatchConnectivity()
        return true
    }

    func configureAppForTesting() -> Void {
        UIView.setAnimationsEnabled(false)
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        
        // Initialize the stored UserDefaultsData
        TreatmentsStream.singleton.treatments = UserDefaultsRepository.treatments.value
        
        let rootViewController = UIStoryboard(name: "Main", bundle: Bundle.main).instantiateInitialViewController()

        self.window = UserInteractionDetectorWindow(frame: UIScreen.main.bounds)
        if #available(iOS 13.0, *) {
            // Always force a dark theme for nightguard. Otherwise e.g. the file picker would be white ^^
            self.window?.overrideUserInterfaceStyle = .dark
        }
        self.window?.rootViewController = rootViewController
        self.window?.makeKeyAndVisible()
        
        dimScreenOnIdle()
        
        // Enable Background Updates
        BGTaskScheduler.shared.register(forTaskWithIdentifier: appProcessingTaskId, using: nil) { task in

            self.handelBackgroundProcessing(task as! BGProcessingTask)
        }
        
        return true
    }
    
    func handelBackgroundProcessing(_ task: BGProcessingTask) {
        
        let _ = NightscoutCacheService.singleton.loadCurrentNightscoutData { result in
            
            guard let result = result else {
                task.setTaskCompleted(success: false)
                return
            }
            
            switch result {
            case .error(let error):
                NSLog("handelBackgroundProcessing - unable to load current Nightscout Data: \(error)")
                task.setTaskCompleted(success: false)
            case .data(let nightscoutData):
                // The new data has already been stored locally. Use it to determine wheter alerts have to be send:
                AlarmNotificationService.singleton.notifyIfAlarmActivated(nightscoutData)
                WatchService.singleton.sendToWatchCurrentNightwatchData()
                task.setTaskCompleted(success: true)
            }
        }
        
        scheduleBackgroundProcessing()
    }
    
    func scheduleBackgroundProcessing() {
         let request = BGProcessingTaskRequest(identifier: appProcessingTaskId)
         request.requiresNetworkConnectivity = true
         request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

         do {
             BGTaskScheduler.shared.cancelAllTaskRequests()
             try BGTaskScheduler.shared.submit(request)
         } catch {
             print("Could not schedule background fetch: \(error)")
         }
     }
    
    func dimScreenOnIdle() {
        
        guard let window = self.window as? UserInteractionDetectorWindow else {
            return
        }
        
        let updateWindowUserInteractionTimeout = {
            if SharedUserDefaultsRepository.screenlockSwitchState.value {
                window.timeout = TimeInterval(UserDefaultsRepository.dimScreenWhenIdle.value * 60)
            } else {
                window.timeout = nil
            }
        }
        
        // bind dim screen settings with user interaction detector window timeout
        UserDefaultsRepository.dimScreenWhenIdle.observeChanges { _ in
            updateWindowUserInteractionTimeout()
        }
        SharedUserDefaultsRepository.screenlockSwitchState.observeChanges { _ in
            updateWindowUserInteractionTimeout()
        }
        
        updateWindowUserInteractionTimeout()
    }

    func activateWatchConnectivity() {
        if WCSession.isSupported() {
            session = WCSession.default
        
            handleWatchMessages()
        }
    }
    
    func handleWatchMessages() {
        
        // snooze message
        WatchMessageService.singleton.onMessage { (message: SnoozeMessage) in
            
            // update snooze from message
            AlarmRule.snoozeFromMessage(message)
        }
        
        // request night safe phone settings
        WatchMessageService.singleton.onRequest { (request: RequestNightSafeMessage) in
            return ResponseNightSafeMessage(
                PhoneNightSafeSettings(
                    isPhoneActive: UIApplication.shared.applicationState == .active,
                    isScreenLockActive: UIApplication.shared.isIdleTimerDisabled,
                    volumeLevel: AlarmSound.overrideSystemOutputVolume.value ? AlarmSound.systemOutputVolume.value : MPVolumeView.volume
                )
            )
        }        
        
        WatchMessageService.singleton.onMessage { (message: WatchSyncRequestMessage) in
            
            // compare the "last sync update id" received from watch and compare it with phone value: if not equal, the watch has not the latest user defaults data and a sync should be performed
            if let anyWatchUpdateId = message.dictionary[UserDefaultsRepository.lastWatchSyncUpdateId.key] {
                let watchUpdateId = type(of: UserDefaultsRepository.lastWatchSyncUpdateId).ValueType.fromAny(anyWatchUpdateId)
                if UserDefaultsRepository.lastWatchSyncUpdateId.value != watchUpdateId {
                    
                    // perform sync!
                    UserDefaultSyncMessage().send()
                
                    print("Handling WatchSyncRequestMessage: UUID on watch didn't match phone UUID")
                }
            }
            
            // same comparison for snoozing timestamp
            if let anyWatchSnoozeTimestamp = message.dictionary["snoozedUntilTimestamp"] {
                let watchSnoozeTimestamp = anyWatchSnoozeTimestamp as? TimeInterval
                if AlarmRule.snoozedUntilTimestamp.value != watchSnoozeTimestamp {
                    
                    // send snooze data to watch!
                    SnoozeMessage(timestamp: AlarmRule.snoozedUntilTimestamp.value).send()
                    
                    print("Handling WatchSyncRequestMessage: Snooze timestamp on watch didn't match phone snooze timestamp")
                }
            }
        }

        
        // whenever a value from the "watch sync" group changes, send the apropriate watch message containing all the group values
        UserDefaultsValueGroups.observeChanges(in: UserDefaultsValueGroups.GroupNames.watchSync) { _, _ in
            
            UserDefaultsRepository.lastWatchSyncUpdateId.value = UUID().uuidString
            UserDefaultSyncMessage().send()
        }
    }
    
    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
        
        // Store all treatments in UserDefaults
        UserDefaultsRepository.treatments.value = TreatmentsStream.singleton.treatments
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
        
        // Store the In-Memory Treatments
        UserDefaultsRepository.treatments.value = TreatmentsStream.singleton.treatments
        
        // Schedule Background Updates:
        self.scheduleBackgroundProcessing()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }
}

