//
//  MeshbluBeaconKit.swift
//  Pods
//
//  Created by Octoblu on 6/1/15.
//
//

import Foundation
import CoreLocation
import MeshbluHttp
import SwiftyJSON
import Dollar
import Result

@objc public protocol MeshbluBeaconKitDelegate {
  optional  func proximityChanged(response: [String: AnyObject])
  optional  func beaconEnteredRegion()
  optional  func beaconExitedRegion()
  optional  func meshbluBeaconIsNotRegistered()
  optional  func meshbluBeaconRegistrationSuccess(device: [String: AnyObject])
  optional  func meshbluBeaconRegistrationFailure(error: NSError)
}

@objc (MeshbluBeaconKit) public class MeshbluBeaconKit: NSObject, CLLocationManagerDelegate {
  
  var lastProximity = CLProximity.Unknown
  var beaconTypes : [String: String] = [:]
  var meshbluHttp : MeshbluHttp
  var delegate: MeshbluBeaconKitDelegate
  let locationManager = CLLocationManager()
  var debug = false;
  var meshbluConfig : [String: AnyObject]!
  
  public init(meshbluConfig: [String: AnyObject], delegate: MeshbluBeaconKitDelegate) {
    self.meshbluHttp = MeshbluHttp(meshbluConfig: meshbluConfig)
    self.meshbluConfig = meshbluConfig
    let uuid = meshbluConfig["uuid"] as? String
    let token = meshbluConfig["token"] as? String
    if uuid != nil && token != nil {
      self.meshbluHttp.setCredentials(uuid!, token: token!)
    }
    self.delegate = delegate
    super.init()
  }
  
  public init(meshbluHttp: MeshbluHttp, delegate: MeshbluBeaconKitDelegate) {
    self.meshbluHttp = meshbluHttp
    self.delegate = delegate
    self.meshbluConfig = [:]
    super.init()
  }
  
  public func getMeshbluClient() -> MeshbluHttp {
    return self.meshbluHttp
  }
  
  public func enableDebug(){
    self.debug = true
  }
  
  private func debugln(message: String){
    if !self.debug {
      return
    }
    
    print(message)
  }
  
  public func start(beaconTypes: [String:String]) {
    startLocationMonitoring()
    
    for (uuid, identifier) in beaconTypes {
      startBeacon(uuid, identifier: identifier);
    }
    
    if self.isNotRegistered() {
      self.delegate.meshbluBeaconIsNotRegistered!()
    }
  }
  
  public func isNotRegistered() -> Bool {
    return self.meshbluConfig["uuid"] == nil
  }
  
  private func startBeacon(uuid: String, identifier: String){
    let beaconUuid : NSUUID? = NSUUID(UUIDString: uuid)
    let beaconRegion = CLBeaconRegion(proximityUUID: beaconUuid!, identifier: identifier)
    locationManager.startMonitoringForRegion(beaconRegion)
    locationManager.startRangingBeaconsInRegion(beaconRegion)
  }
  
  private func startLocationMonitoring(){
    if(locationManager.respondsToSelector("requestAlwaysAuthorization")) {
      if CLLocationManager.authorizationStatus() == .NotDetermined {
        locationManager.requestAlwaysAuthorization()
      }
    }
    
    locationManager.delegate = self
    locationManager.pausesLocationUpdatesAutomatically = false
    
    if CLLocationManager.locationServicesEnabled() {
      locationManager.startUpdatingLocation()
      locationManager.startUpdatingHeading()
    }
  }
  
  public func register() {
    register([:])
  }
  
  public func register(data: [String:AnyObject]) {
    let device = ["type": "device:beacon-blu", "online" : "true"] as [String: AnyObject]
    let mergedDevice = $.merge(device, data)
    
    self.meshbluHttp.register(mergedDevice) { (result) -> () in
      switch result {
      case .Failure(_):
        self.delegate.meshbluBeaconRegistrationFailure!(result.error!)
      case let .Success(success):
        let json = success
        let uuid = json["uuid"].stringValue
        let token = json["token"].stringValue
        
        self.meshbluHttp.setCredentials(uuid, token: token)
        
        var data = ["uuid": uuid, "token": token]
        self.delegate.meshbluBeaconRegistrationSuccess!(data)
      }
    }
  }
  
  public func locationManager(manager: CLLocationManager, didRangeBeacons beacons: [CLBeacon], inRegion region: CLBeaconRegion) {
    var code = 0
    var message = "Unknown"
    var nearestBeacon = CLBeacon()
    
    if(beacons.count > 0) {
      nearestBeacon = beacons[0]
    }
    
    if(nearestBeacon.proximity == lastProximity) {
      return;
    }
    
    lastProximity = nearestBeacon.proximity;
    
    switch nearestBeacon.proximity {
    case CLProximity.Far:
      code = 3
      message = "Far"
    case CLProximity.Near:
      code = 2
      message = "Near"
    case CLProximity.Immediate:
      code = 1
      message = "Immediate"
    case CLProximity.Unknown:
      code = 0
      message = "Unknown"
    }
    
    debugln("\(self.locationManager.location)")
    
    let location = self.locationManager.location
    let heading = self.locationManager.heading
    
    let dateFor = NSDateFormatter()
    dateFor.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
    
    let proximityUuid = nearestBeacon.proximityUUID
    if proximityUuid.UUIDString.isEmpty {
      return self.debugln("No proximity uuid. Not sending location")
    }
    
    var response : [String: AnyObject] = [
      "platform": "ios",
      "version": NSProcessInfo.processInfo().operatingSystemVersionString,
      "libraryVersion": MeshbluBeaconKit.version(),
      "beacon": [
        "uuid": proximityUuid.UUIDString,
        "major": nearestBeacon.major,
        "minor": nearestBeacon.minor
      ],
      "proximity": [
        "message": message,
        "code": code,
        "rssi": nearestBeacon.rssi,
        "accuracy": nearestBeacon.accuracy,
        "timestamp": dateFor.stringFromDate(NSDate())
      ]
    ]
    
    if (location != nil) {
      var level = 0
      if (location!.floor != nil) {
        level = location!.floor!.level
      }
      
      response["location"] = [
        "coordinates": [location!.coordinate.latitude, location!.coordinate.longitude],
        "altitude": location!.altitude,
        "floor": level,
        "horizontalAccuracy": location!.horizontalAccuracy,
        "verticalAccuracy": location!.verticalAccuracy,
        "timestamp": dateFor.stringFromDate(location!.timestamp)
      ]
    }
    
    if (heading != nil) {
      response["heading"] = [
        "magneticHeading": heading!.magneticHeading,
        "trueHeading": heading!.trueHeading,
        "headingAccuracy": heading!.headingAccuracy,
        "timestamp": dateFor.stringFromDate(heading!.timestamp)
      ]
    }
    
    debugln("Sending response: \(response)")
    
    self.delegate.proximityChanged!(response)
  }
  
  public func locationManager(manager: CLLocationManager,
    didChangeAuthorizationStatus status: CLAuthorizationStatus)
  {
    if status == .AuthorizedAlways || status == .AuthorizedWhenInUse {
      manager.startUpdatingLocation()
      manager.startUpdatingHeading()
    }
  }
  
  public func locationManager(manager: CLLocationManager,
    didEnterRegion region: CLRegion) {
      manager.startRangingBeaconsInRegion(region as! CLBeaconRegion)
      manager.startUpdatingLocation()
      
      self.delegate.beaconEnteredRegion!()
  }
  
  public func locationManager(manager: CLLocationManager,
    didExitRegion region: CLRegion) {
      manager.stopRangingBeaconsInRegion(region as! CLBeaconRegion)
      manager.stopUpdatingLocation()
      
      self.delegate.beaconExitedRegion!()
  }
  
  public func sendLocationUpdate(payload: [String: AnyObject], handler: (Result<JSON, NSError>) -> ()){
    let message : [String: AnyObject] = [
      "devices" : ["*"],
      "payload" : payload,
      "topic" : "location_update"
    ]
    
    self.meshbluHttp.message(message) {
      (result) -> () in
      handler(result)
      self.debugln("Message Sent: \(message)")
    }
  }
}
