//
//  ViewController.swift
//  Trip Simulator
//
//  Created by Billy Lo on 2020-07-26.
//

import Cocoa
import MapKit
import CoreLocation

class ViewController: NSViewController, NSComboBoxDelegate {

    private let locationManager = CLLocationManager()
    private var currentLocation: CLPlacemark?
    private var fromPlacemark: MKPlacemark!
    private var toPlacemark: MKPlacemark!
    private var currentPlacemark: MKPlacemark?
    private var currentAnnotation = MovableAnnotation()
    private var allSteps : Array<MKMapPoint> = []
    private var allDurations : Array<TimeInterval> = []
    private let simulationQueue = DispatchQueue(label: "SimulationThread", qos: .background)
    private var simulating = false
    private var stepNum = 0
    private var speedValue : Double = 1.0
    private var fromSearchActive : Bool = true
    
    private var searchCompleter: MKLocalSearchCompleter?
    var completerResults: [MKLocalSearchCompletion]?

    private var route: MKRoute!
    private var bootedSimulators : [Simulator] = []

    private var boundingRegion: MKCoordinateRegion = MKCoordinateRegion(MKMapRect.world)
    @IBOutlet var mapView: MKMapView!
    @IBOutlet var fromOutlet: NSSearchField!

    @IBOutlet var toOutlet: NSSearchField!

    @IBOutlet var speedOutlet: NSComboBox!
    
    @IBOutlet weak var generateButton: NSButton!
    @IBOutlet weak var simulateButton: NSButton!
    @IBOutlet var tableView: NSTableView!
    @IBOutlet var tableScrollView: NSScrollView!
    
    @IBAction func tableAction(_ sender: Any) {

        let tableView = sender as! NSTableView
        let suggestion : MKLocalSearchCompletion? = completerResults?[tableView.selectedRow]
        
        if (fromSearchActive) {
            fromOutlet.stringValue = suggestion!.title
        } else {
            toOutlet.stringValue = suggestion!.title
        }
        
        tableScrollView.isHidden = true
        
    }
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


    fileprivate func loadBootedSimulators() {
        do {
            bootedSimulators = try getBootedSimulators()
        } catch let error {
            print(error)
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        locationManager.delegate = self
        mapView.delegate = self
        speedOutlet.delegate = self
        fromOutlet.becomeFirstResponder()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(textDidChange(_:)),
                                               name: NSSearchField.textDidChangeNotification,
                                               object: nil)

        // Do any additional setup after loading the view.
        assignSpeed()
        tableView.delegate = self
        tableView.dataSource = self

    }

    override func viewWillAppear() {
        super.viewWillAppear()
        startProvidingCompletions()

    }

    override func viewDidAppear() {
        super.viewDidAppear()
        requestLocation()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        stopProvidingCompletions()
    }

    private func startProvidingCompletions() {
        searchCompleter = MKLocalSearchCompleter()
        searchCompleter?.delegate = self
    }

    private func stopProvidingCompletions() {
        searchCompleter = nil
    }
    
    @objc func comboBoxSelectionDidChange(_ notification: Notification) {
        assignSpeed()
    }

    private func assignSpeed() {
        
        var speedStringRaw = speedOutlet.stringValue
        if speedOutlet.indexOfSelectedItem >= 0 {
            speedStringRaw = speedOutlet.itemObjectValue(at: speedOutlet.indexOfSelectedItem) as! String   // strange https://stackoverflow.com/a/5716009
        }
        let speedString = speedStringRaw.replacingOccurrences(of: "x", with: "")
        self.speedValue = Double(speedString) ?? 1.0                       // default to 1X if not convertable
    }
    
    @IBAction func routeAction(_ sender: NSButton) {
        
        print("Route button pressed")
        
        if self.route != nil {        // clear overlay
            self.mapView.removeOverlay(self.route.polyline)
        }

        generateButton.isEnabled = false
        
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
            
            self.generateButton.isEnabled = true

            guard let response = response else {
                if let error = error {
                    print("Error: \(error)")
                }
                return
            }
            
            
            self.route = response.routes[0]
            self.mapView.addOverlay(self.route.polyline)
            self.simulateButton.isEnabled = true
            self.speedOutlet.isEnabled = true

        }

    }

    
    @IBAction func startSimulationAction(_ sender: Any) {
        
        // prepare step array with duration for playback
        
        if (simulating) {
            simulating = false
            simulateButton.state = NSControl.StateValue.off
            simulateButton.title = "Start Simulation"
            self.fromOutlet.isEnabled = true
            self.toOutlet.isEnabled = true
            self.generateButton.isEnabled = true

            return
        } else {
            simulateButton.state = NSControl.StateValue.on
            simulateButton.title = "Stop Simulation"

            var totalDuration = 0.0
            
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

                if (totalDistance > 0) {
                let stepPoints = step.polyline.points()
                    for i in 0..<step.polyline.pointCount {
                        let stepPoint = stepPoints[i]
                        let pointDistance = stepPoint.distance(to: allSteps.last ?? stepPoint)
                        let pointDuration = (pointDistance / totalDistance) * (step.distance / route.distance) * route.expectedTravelTime
                        print("\(i): \(pointDuration) seconds, \(pointDistance)")
                        allDurations.append(pointDuration)
                        allSteps.append(stepPoint)
                        totalDuration += pointDuration
                    }
                }
                
            }
            print("Total Duration = \(round(totalDuration/60)) for \(allSteps.count) steps")
            
            // run simulation on a dedicated thread
            self.fromOutlet.isEnabled = false
            self.toOutlet.isEnabled = false
            self.generateButton.isEnabled = false

            simulationQueue.async{
                self.simulateMovement()
            }
        }
    }
    
    func simulateMovement() {
        
        print("> simulateMovement")
        simulating = true
        stepNum = 0
        
        if (bootedSimulators.count == 0) {
            loadBootedSimulators()                  // try once more
        }
        
        for i in stepNum ..< allSteps.count - 1 {
            
            if (simulating) {
                let step = allSteps[i]
                print("moving to step \(i)")
                DispatchQueue.main.async {
                    self.currentAnnotation.coordinate = step.coordinate
                    self.currentAnnotation.title = "Step \(i)"
                }
                sendToSimulator(coordinate: step.coordinate)
                let sleepTime : UInt32 = UInt32(allDurations[i] * 1000000 / speedValue)
                
                // enhancement: if sleepTime > 1 second, stage the movement between current step and next step
                usleep(sleepTime)
            } else {
                return
            }
        }
        simulating = false
        return
        
    }
        
    func sendToSimulator(coordinate: CLLocationCoordinate2D) {
        
        let simulators = bootedSimulators
        postNotification(for: coordinate, to: simulators.map { $0.udid.uuidString })
        print("Setting location to \(coordinate.latitude) \(coordinate.longitude)")
        
    }
    
    // if user switches between from and to search fields, update searchCompleter
    
    @IBAction func searchFieldAction(_ sender: Any) {
        
        print("searchFieldAction")
        let field = sender as! NSSearchField
        guard let queryString = field.cell?.stringValue else {
            return
        }
        searchCompleter?.queryFragment = queryString
    }
    
    
    @objc func textDidChange(_ obj: Notification) {
        
        if obj.object is NSSearchField {
            
            let field = obj.object as! NSSearchField
            if ((field.identifier?.rawValue.contains("Field")) != nil) {
                
                // print("search for queryString")
                
                fromSearchActive = (field.identifier!.rawValue == "fromField")        // so the other code can tell we are working on from or to field
                
                guard let queryString = field.cell?.stringValue else {
                    return
                }
                searchCompleter?.queryFragment = queryString
/*
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

                        if (fieldId == "toField") {
                            outlet = self.toOutlet
                            self.toPlacemark = item.placemark
                        } else {
                            outlet = self.fromOutlet
                            self.fromPlacemark = item.placemark
                            self.toOutlet.becomeFirstResponder()
                        }
                        outlet?.stringValue = item.placemark.name!
                    }
                }
                 if (self.fromPlacemark != nil) && (self.toPlacemark != nil) {
                     self.generateButton.isEnabled = true
                 } else {
                     self.generateButton.isEnabled = false
                 }
                 

 */
            } else {        // changed speed
                assignSpeed()
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

extension ViewController: MKLocalSearchCompleterDelegate {
    
    /// - Tag: QueryResults
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        // As the user types, new completion suggestions are continuously returned to this method.
        // Overwrite the existing results, and then refresh the UI with the new results.
        completerResults = completer.results
        if completerResults!.count > 0 {
            tableView.isHidden = false
        }
        tableView.reloadData()
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        // Handle any errors returned from MKLocalSearchCompleter.
        if let error = error as NSError? {
            print("MKLocalSearchCompleter encountered an error: \(error.localizedDescription). The query fragment is: \"\(completer.queryFragment)\"")
        }
    }
}


extension CLLocationCoordinate2D {
    //distance in meters, as explained in CLLoactionDistance definition
    func distance(from: CLLocationCoordinate2D) -> CLLocationDistance {
        let destination=CLLocation(latitude:from.latitude,longitude:from.longitude)
        return CLLocation(latitude: latitude, longitude: longitude).distance(from: destination)
    }
}

// suggestionTableDelegate methods

extension ViewController: NSTableViewDataSource {
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        
        let rowCount = completerResults?.count ?? 0
        if (rowCount > 0) {
            tableScrollView.isHidden = false
        }
        return rowCount
    }
}


extension ViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        
        let cellIdentifier = NSUserInterfaceItemIdentifier(rawValue: "cell")
        guard let cell = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView else { return nil }
        
        if let suggestion = completerResults?[row] {
            // Each suggestion is a MKLocalSearchCompletion with a title, subtitle, and ranges describing what part of the title
            // and subtitle matched the current query string. The ranges can be used to apply helpful highlighting of the text in
            // the completion suggestion that matches the current query fragment.
            cell.textField?.stringValue = suggestion.title
        }
        
        return cell
    }
}

/*
extension ViewController {
    
    
    
    
    /// - Tag: HighlightFragment
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SuggestedCompletionTableViewCell.reuseID, for: indexPath)

        if let suggestion = completerResults?[indexPath.row] {
            // Each suggestion is a MKLocalSearchCompletion with a title, subtitle, and ranges describing what part of the title
            // and subtitle matched the current query string. The ranges can be used to apply helpful highlighting of the text in
            // the completion suggestion that matches the current query fragment.
            cell.textLabel?.attributedText = createHighlightedString(text: suggestion.title, rangeValues: suggestion.titleHighlightRanges)
            cell.detailTextLabel?.attributedText = createHighlightedString(text: suggestion.subtitle, rangeValues: suggestion.subtitleHighlightRanges)
        }

        return cell
    }
    
    private func createHighlightedString(text: String, rangeValues: [NSValue]) -> NSAttributedString {
        let attributes = [NSAttributedString.Key.backgroundColor: UIColor(named: "suggestionHighlight")! ]
        let highlightedString = NSMutableAttributedString(string: text)
        
        // Each `NSValue` wraps an `NSRange` that can be used as a style attribute's range with `NSAttributedString`.
        let ranges = rangeValues.map { $0.rangeValue }
        ranges.forEach { (range) in
            highlightedString.addAttributes(attributes, range: range)
        }
        
        return highlightedString
    }
}
*/


class MovableAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    @objc dynamic var title: String?

    //Add your custom code here
    override init() {
        coordinate = CLLocationCoordinate2DMake(0,0)
        super.init()
    }
}

private class SuggestedCompletionTableCellView: NSTableCellView {
    
    static let reuseID = "SuggestedCompletionTableCellViewReuseID"
    
}
