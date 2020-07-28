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
    @IBOutlet var map: MKMapView!
    @IBOutlet var fromOutlet: NSSearchField!

    private var localSearch: MKLocalSearch? {
        willSet {
            // Clear the results and cancel the currently running local search before starting a new search.
            // places = nil
            localSearch?.cancel()
        }
    }

    private var places: [MKMapItem]? {
        didSet {
            // tableView.reloadData()
            // viewAllButton.isEnabled = places != nil
        }
    }


    override func viewDidLoad() {
        super.viewDidLoad()
        locationManager.delegate = self
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(textDidEndEditing(_:)),
                                               name: NSSearchField.textDidEndEditingNotification,
                                               object: nil)

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

    @objc func textDidEndEditing(_ obj: Notification) {
        
        let fromField = obj.object as! NSSearchField
        let searchString = fromField.cell?.stringValue ?? "unknown"
        print(searchString)
        search(for: searchString)

    }

    @IBAction func routeAction(_ sender: NSButton) {
        
        print("Route button pressed")
    }
    

    /// - Parameter queryString: A search string from the text the user entered
    
    private func search(for queryString: String?) {
        
        print("search for queryString")
        let searchRequest = MKLocalSearch.Request()
        searchRequest.naturalLanguageQuery = queryString
        search(using: searchRequest)
        
    }
    
    /// - Tag: SearchRequest
    private func search(using searchRequest: MKLocalSearch.Request) {
        // Confine the map search area to an area around the user's current location.
        searchRequest.region = boundingRegion
        
        // Include only point of interest results. This excludes results based on address matches.
        // searchRequest.resultTypes = .pointOfInterest
        
        localSearch = MKLocalSearch(request: searchRequest)
        localSearch?.start { [unowned self] (response, error) in
            guard error == nil else {
                self.displaySearchError(error)
                return
            }
            
            self.places = response?.mapItems
            
        }
    }
    
    private func displaySearchError(_ error: Error?) {
        
        if let error = error as NSError?, let errorString = error.userInfo[NSLocalizedDescriptionKey] as? String {
            
            let alert = NSAlert()
            alert.messageText = "Could not find any places."
            alert.informativeText = errorString
            alert.beginSheetModal(for: self.view.window!) { (response) in }

        }
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
        alert.informativeText = "Simulator will continue to work. Starting location won't be set."
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

