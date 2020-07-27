//
//  ViewController.swift
//  Trip Simulator
//
//  Created by Billy Lo on 2020-07-26.
//

import Cocoa
import MapKit
import CoreLocation

class ViewController: NSViewController {

    private let locationManager = CLLocationManager()
    private var currentPlacemark: CLPlacemark?
    private var boundingRegion: MKCoordinateRegion = MKCoordinateRegion(MKMapRect.world)

    override func viewDidLoad() {
        super.viewDidLoad()
        locationManager.delegate = self

        // Do any additional setup after loading the view.
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        requestLocation()
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }

    @IBOutlet var map: MKMapView!
    
    @IBAction func fromAction(_ sender: NSSearchField) {
        
        
        
    }
}

// MARK: - Location Handling

extension ViewController {
    private func requestLocation() {
        guard CLLocationManager.locationServicesEnabled() else {
            displayLocationServicesDisabledAlert()
            return
        }
        
        let status = CLLocationManager.authorizationStatus()
        guard status != .denied else {
            displayLocationServicesDeniedAlert()
            return
        }
        
        locationManager.requestLocation()
    }
    
    private func displayLocationServicesDisabledAlert() {
        let message = NSLocalizedString("LOCATION_SERVICES_DISABLED", comment: "Location services are disabled")
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = "Simulator will continue to work."
        alert.beginSheetModal(for: self.view.window!) { (response) in

        }
    }
    
    private func displayLocationServicesDeniedAlert() {
        let message = NSLocalizedString("LOCATION_SERVICES_DENIED", comment: "Location services are denied")
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = "Simulator will continue to work."
        alert.beginSheetModal(for: self.view.window!) { (response) in }
    }
}

extension ViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // https://stackoverflow.com/a/11519772
        
        let region = MKCoordinateRegion( center: location.coordinate, latitudinalMeters: CLLocationDistance(exactly: 5000)!, longitudinalMeters: CLLocationDistance(exactly: 5000)!)
        map.setRegion(map.regionThatFits(region), animated: true)

        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { (placemark, error) in
            guard error == nil else { return }
            
            self.currentPlacemark = placemark?.first
            self.boundingRegion = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 12_000, longitudinalMeters: 12_000)
            // self.suggestionController.updatePlacemark(self.currentPlacemark, boundingRegion: self.boundingRegion)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Handle any errors returned from Location Services.
    }
}

