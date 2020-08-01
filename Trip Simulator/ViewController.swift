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
    private var currentLocation: CLPlacemark?
    private var fromPlacemark: MKPlacemark!
    private var toPlacemark: MKPlacemark!
    private var currentPlacemark: MKPlacemark?
    private var currentAnnotation = MovableAnnotation()

    private var route: MKRoute!

    private var boundingRegion: MKCoordinateRegion = MKCoordinateRegion(MKMapRect.world)
    @IBOutlet var mapView: MKMapView!
    @IBOutlet var fromOutlet: NSSearchField!
    @IBOutlet var toOutlet: NSSearchField!
    
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
        mapView.delegate = self
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
    
    @IBAction func routeAction(_ sender: NSButton) {
        
        print("Route button pressed")
        
        // 4.
        let sourceMapItem = MKMapItem(placemark: fromPlacemark)
        let destinationMapItem = MKMapItem(placemark: toPlacemark)
        
        // 5.
        let sourceAnnotation = MKPointAnnotation()
        sourceAnnotation.title = fromPlacemark.title
        sourceAnnotation.coordinate = fromPlacemark.coordinate
        
        
        let destinationAnnotation = MKPointAnnotation()
        destinationAnnotation.title = toPlacemark.title
        destinationAnnotation.coordinate = toPlacemark.coordinate
        
        currentAnnotation.coordinate = fromPlacemark.coordinate
        
        // 6.
        self.mapView.showAnnotations([sourceAnnotation,destinationAnnotation,self.currentAnnotation], animated: true )
        
        // 7.
        let directionRequest = MKDirections.Request()
        directionRequest.source = sourceMapItem
        directionRequest.destination = destinationMapItem
        directionRequest.transportType = .automobile
        
        // Calculate the direction
        let directions = MKDirections(request: directionRequest)
        
        // 8.
        directions.calculate {
            (response, error) -> Void in
            
            guard let response = response else {
                if let error = error {
                    print("Error: \(error)")
                }
                
                return
            }
            
            self.route = response.routes[0]
            self.mapView.addOverlay(self.route.polyline)

        }

    }

    
    @IBAction func startSimulationAction(_ sender: Any) {
        
        var currentStepPoint : MKMapPoint
        let timer = Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(updateAnnotationCoordinates), userInfo: currentStepPoint, repeats: true)

        for step in route.steps {
            
            var coordinates: [CLLocationCoordinate2D] = Array(repeating: kCLLocationCoordinate2DInvalid, count: step.polyline.pointCount)
            step.polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: step.polyline.pointCount))
            var totalDistance = 0.0
            
            // calculate total distance to determine percentage completion
            for i in 0..<step.polyline.pointCount {
                let coord = coordinates[i]
                if (i > 0) {
                    totalDistance += (coord.distance(from: coordinates[i-1]))
                }
            }

            let stepPoints = step.polyline.points()
            for i in 0..<step.polyline.pointCount {
                let stepPoint = stepPoints[i]
                perform(#selector(updateAnnotationCoordinates(stepPoint:)), with: stepPoint, afterDelay: 1)
            }

        }
        
    }
    
    @objc func updateAnnotationCoordinates( stepPoint: MKMapPoint) {
        
        currentAnnotation.coordinate = stepPoint.coordinate;
        
    }
    
    @objc func textDidEndEditing(_ obj: Notification) {
        
        let field = obj.object as! NSSearchField
        print("search for queryString")
        let searchRequest = MKLocalSearch.Request()
        searchRequest.naturalLanguageQuery = field.cell?.stringValue
        searchRequest.region = boundingRegion
        
        localSearch = MKLocalSearch(request: searchRequest)
        localSearch?.start { [unowned self] (response, error) in
            guard error == nil else {
                self.displaySearchError(error)
                return
            }
            
            self.places = response?.mapItems
            let fieldId = (field.identifier?.rawValue ?? "") as String
            let items = response?.mapItems;
            if (items!.count > 0) {
                let item = items![0]
                var outlet : NSSearchField!

                if (fieldId == "to") {
                    outlet = self.toOutlet
                    self.toPlacemark = item.placemark
                } else {
                    outlet = self.fromOutlet
                    self.fromPlacemark = item.placemark
                }
                outlet?.stringValue = item.placemark.name!
            }
            
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
        mapView.setRegion(mapView.regionThatFits(region), animated: true)

        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { (placemark, error) in
            guard error == nil else { return }
            
            self.currentLocation = placemark?.first
            self.boundingRegion = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 12_000, longitudinalMeters: 12_000)
            // self.suggestionController.updatePlacemark(self.currentPlacemark, boundingRegion: self.boundingRegion)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Handle any errors returned from Location Services.
    }
}

extension ViewController: MKMapViewDelegate {
    
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if overlay.isKind(of: MKPolyline.self) {
            // draw the track
            let polyLine = overlay
            let polyLineRenderer = MKPolylineRenderer(overlay: polyLine)
            polyLineRenderer.strokeColor = NSColor.blue
            polyLineRenderer.lineWidth = 3.0

            return polyLineRenderer
        }

        return MKPolylineRenderer()
    }

}

extension CLLocationCoordinate2D {
    //distance in meters, as explained in CLLoactionDistance definition
    func distance(from: CLLocationCoordinate2D) -> CLLocationDistance {
        let destination=CLLocation(latitude:from.latitude,longitude:from.longitude)
        return CLLocation(latitude: latitude, longitude: longitude).distance(from: destination)
    }
}

class MovableAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    //Add your custom code here
    override init() {
        coordinate = CLLocationCoordinate2DMake(0,0)
        super.init()
    }
}
