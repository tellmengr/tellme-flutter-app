import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private func googleMapsApiKey() -> String? {
    if let infoKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String,
       !infoKey.isEmpty,
       !infoKey.contains("$(") {
      return infoKey
    }

    guard
      let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
      let plist = NSDictionary(contentsOfFile: path),
      let firebaseKey = plist["API_KEY"] as? String,
      !firebaseKey.isEmpty
    else {
      return nil
    }

    return firebaseKey
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let mapsKey = googleMapsApiKey() {
      GMSServices.provideAPIKey(mapsKey)
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
