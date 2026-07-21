//
//  AppDelegate.swift
//  ChunithmController
//
//  Created by Alen Cat on 2026/7/3.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // 沒有用 Storyboard，直接在程式碼裡建立畫面
        // （沒有宣告 UIScene，走傳統 AppDelegate 生命週期，簡單夠用）
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = ViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Insert code here to tear down your application
    }
}
