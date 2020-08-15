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
    private var fromSearchFieldActive : Bool = true
    private var currentAnnotationView = MKAnnotationView()
    private let sourceAnnotation = MovableAnnotation()
    private let destinationAnnotation = MovableAnnotation()

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
    @IBOutlet var statusOutlet: NSTextField!
    
    @IBAction func tableAction(_ sender: Any) {

        let tableView = sender as! NSTableView
        let suggestion : MKLocalSearchCompletion? = completerResults?[tableView.selectedRow]
        
        if fromSearchFieldActive {
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
        speedOutlet.selectItem(at: 1)       // for some reasons, the first row cannot be selected by user, default to 5x
        requestLocation()

    }

    override func viewWillAppear() {
        super.viewWillAppear()
        startProvidingCompletions()

    }

    override func viewDidAppear() {
        super.viewDidAppear()
        fromOutlet.becomeFirstResponder()
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
        
        let sourceMapItem = MKMapItem(placemark: fromPlacemark)
        let destinationMapItem = MKMapItem(placemark: toPlacemark)
        
        sourceAnnotation.title = fromPlacemark.title
        sourceAnnotation.coordinate = fromPlacemark.coordinate
                
        destinationAnnotation.title = toPlacemark.title
        destinationAnnotation.coordinate = toPlacemark.coordinate
        
        currentAnnotation.coordinate = fromPlacemark.coordinate
        
        self.mapView.showAnnotations([sourceAnnotation,destinationAnnotation,self.currentAnnotation], animated: true )
        
        let directionRequest = MKDirections.Request()
        directionRequest.source = sourceMapItem
        directionRequest.destination = destinationMapItem
        directionRequest.transportType = .automobile
        
        // Calculate the direction
        let directions = MKDirections(request: directionRequest)
        
        statusOutlet.stringValue = "Generating route..."

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
            
            DispatchQueue.main.async {
                self.mapView.addOverlay(self.route.polyline)
                self.simulateButton.isEnabled = true
                self.speedOutlet.isEnabled = true
                let durationInMin = round(self.route.expectedTravelTime / 60)
                self.statusOutlet.stringValue = "Route generated. Trip duration = \(durationInMin) min."
                self.simulateButton.isHighlighted = true
            }

        }

    }

    
    @IBAction func startSimulationAction(_ sender: Any) {
        
        // prepare step array with duration for playback
        
        if (simulating) {
            
            simulating = false
            simulateButton.state = NSControl.StateValue.off
            simulateButton.title = "Start Simulation"
            fromOutlet.isEnabled = true
            toOutlet.isEnabled = true
            generateButton.isEnabled = true
            currentAnnotationView.isEnabled = false
            // currentAnnotation.coordinate = fromPlacemark.coordinate         // return to starting point
            
        } else {
            
            simulateButton.state = NSControl.StateValue.on
            currentAnnotationView.isEnabled = true
            simulateButton.title = "Stop Simulation"
            self.generateButton.isEnabled = true
            
            var totalDuration = 0.0
            allDurations.removeAll()
            allSteps.removeAll()
            
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
        tableScrollView.isHidden = true         // clean up
        fromOutlet.isEnabled = true
        toOutlet.isEnabled = true
        generateButton.isEnabled = true

    }
    
    func simulateMovement() {
        
        print("> simulateMovement")
        let refreshInterval : Double = 0.5
        simulating = true
        stepNum = 0
        
        if (bootedSimulators.count == 0) {
            self.loadBootedSimulators()
        }
        
        for i in stepNum ..< allSteps.count - 1 {                           // all steps loop
            
            if (simulating) {
                let step = allSteps[i]
                let sleepTime : Double = allDurations[i] / speedValue         // in seconds (total for the step)
                let lastSubStep : Int = Int(floor(sleepTime / refreshInterval)) 
                // print("moving to step \(i), lastSubStep = \(lastSubStep), sleepTime = \(sleepTime)")
                var simulationCoordinate : CLLocationCoordinate2D
                var substep = 0

                repeat {                                                    // substep loop

                    var subStepSleep : Double = sleepTime                   // default,  in seconds
                    if (lastSubStep == 0) {
                        simulationCoordinate = step.coordinate
                    } else {
                        if i < (allSteps.count - 1) {
                            let dLat : Double = allSteps[i+1].coordinate.latitude - step.coordinate.latitude
                            let dLng : Double = allSteps[i+1].coordinate.longitude - step.coordinate.longitude
                            var simulationLat, simulationLng : Double
                            if substep < (lastSubStep) {          // before last substep
                                subStepSleep = refreshInterval
                                simulationLat = step.coordinate.latitude + (dLat * refreshInterval * Double(substep) / sleepTime)
                                simulationLng = step.coordinate.longitude + (dLng * refreshInterval * Double(substep) / sleepTime)
                            } else {
                                subStepSleep = sleepTime - (Double(substep)*refreshInterval)
                                simulationLat = step.coordinate.latitude + (dLat * (1 - subStepSleep / sleepTime))          // remaining time
                                simulationLng = step.coordinate.longitude + (dLng * (1 - subStepSleep / sleepTime))
                            }
                            simulationCoordinate = CLLocationCoordinate2DMake(simulationLat, simulationLng)
                        } else {
                            simulationCoordinate = step.coordinate
                        }
                    }
                    
                    print("Step \(i).\(substep) - " +
                        "\(String(format:"%.6f",simulationCoordinate.latitude))," +
                        "\(String(format:"%.6f",simulationCoordinate.longitude)), " +
                        "subStepSleep = \(String(format:"%.1f",subStepSleep)), " +
                        "totalSleep = \(String(format:"%.1f",sleepTime))"
                    )

                    DispatchQueue.main.sync {
                        self.statusOutlet.stringValue = "Step \(i).\(substep) - \(String(format:"%.6f",simulationCoordinate.latitude))," + "\(String(format:"%.6f",simulationCoordinate.longitude)), duration = \(String(format:"%.1f",subStepSleep)) sec"
                        self.sendToSimulator(coordinate: simulationCoordinate)
                    }

                    usleep(UInt32(subStepSleep*1e6))

                    substep += 1
                    
                } while (substep <= lastSubStep) && (simulating)
                
            } else {
                return
            }
        }
        simulating = false
        
        //re-enable simulate buttons
        DispatchQueue.main.async {
            self.simulateButton.isEnabled = true
            self.simulateButton.title = "Start Simulation"
            self.simulateButton.state = NSControl.StateValue.off
            self.tableScrollView.isHidden = true
        }
        
        return
        
    }
    

    
    func sendToSimulator(coordinate: CLLocationCoordinate2D) {
        
        
//    - (void)rotateByNumber:(NSNumber*)angle {
//            self.layer.position = CGPointMake(NSMidX(self.frame), NSMidY(self.frame));
//            self.layer.anchorPoint = CGPointMake(.5, .5);
//            self.layer.affineTransform = CGAffineTransformMakeRotation(angle.floatValue);
//        }
        
        currentAnnotation.coordinate = coordinate

        let simulators = bootedSimulators
        postNotification(for: coordinate, to: simulators.map { $0.udid.uuidString })
        // print("Setting location to \(coordinate.latitude) \(coordinate.longitude)")
        
    }
    
    // if user switches between from and to search fields, update searchCompleter
    
    @IBAction func searchFieldAction(_ sender: Any) {
        
        // print("searchFieldAction")
        let field = sender as! NSSearchField
        guard let queryString = field.cell?.stringValue else {
            return
        }
        searchCompleter?.queryFragment = queryString
    }
    
// https://stackoverflow.com/a/45851169/2789065
    
    func isTextFieldInFocus(_ textField: NSTextField) -> Bool {
        
        var inFocus : Bool! = false
        inFocus = (textField.window?.firstResponder?.isKind(of: NSTextView.self))!
            && (textField.window?.fieldEditor(false, for: nil) != nil)
            && (textField == ((textField.window?.firstResponder as! NSTextView).delegate as! NSTextField))
        
        return inFocus
        
    }
    
    func fromSearchFieldActiveTest() -> Bool {
        
        return isTextFieldInFocus(self.fromOutlet)
        
    }
    
    @objc func textDidChange(_ obj: Notification) {
        
        if obj.object is NSSearchField {
                        
            let field = obj.object as! NSSearchField
            if ((field.identifier?.rawValue.contains("Field")) != nil) {
                
                // print("search for queryString")
                let newSearchFieldActive: Bool = (field.identifier!.rawValue == "fromField")
                
                if (fromSearchFieldActive != newSearchFieldActive) {
                    
                    // switch suggestion box location
                    let currentY : CGFloat = tableScrollView.frame.minY
                    let fromX : CGFloat = fromOutlet.frame.minX
                    let toX : CGFloat = toOutlet.frame.minX

                    if (newSearchFieldActive) {
                        tableScrollView.setFrameOrigin(NSPoint.init(x: fromX, y: currentY))
                    } else {
                        tableScrollView.setFrameOrigin(NSPoint.init(x: toX, y: currentY))
                    }
                    fromSearchFieldActive = newSearchFieldActive       // so the other code can tell we are working on from or to field

                }
                
                guard let queryString = field.cell?.stringValue else {
                    return
                }
                searchCompleter?.queryFragment = queryString

            } else {        // changed speed
                assignSpeed()
                tableScrollView.isHidden = true     // clean up
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
    
    func lookupAndAddPlacemark(_ title: String) {
        
        let searchRequest = MKLocalSearch.Request()
        searchRequest.naturalLanguageQuery = title
        // searchRequest.region = boundingRegion
        
        localSearch = MKLocalSearch(request: searchRequest)
        localSearch?.start { [unowned self] (response, error) in
            guard error == nil else {
                self.displaySearchError(error)
                return
            }
            
            self.places = response?.mapItems
            let items = response?.mapItems;
            if (items!.count > 0) {
                let item = items![0]
                if (!self.fromSearchFieldActive) {
                    self.toPlacemark = item.placemark
                } else {
                    self.fromPlacemark = item.placemark
                    self.toOutlet.becomeFirstResponder()
                }
            }
            if (self.fromPlacemark != nil) && (self.toPlacemark != nil) {
                self.generateButton.isHighlighted = true
                self.generateButton.isEnabled = true
            } else {
                self.generateButton.isHighlighted = false
                self.generateButton.isEnabled = false
            }
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
        searchCompleter?.region = region

        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { (placemark, error) in
            guard error == nil else { return }
            
            self.currentLocation = placemark?.first
            self.boundingRegion = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 12_000, longitudinalMeters: 12_000)
        }
        locationManager.stopUpdatingLocation()                  // only once is sufficent
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print(error)
    }
}

extension ViewController: MKMapViewDelegate {
    
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if overlay.isKind(of: MKPolyline.self) {
            // draw the track
            let polyLine = overlay
            let polyLineRenderer = MKPolylineRenderer(overlay: polyLine)
            
            // set region https://stackoverflow.com/a/32013953/2789065
            
            let mapRect = MKPolygon(points: polyLineRenderer.polyline.points(), count: polyLineRenderer.polyline.pointCount)
            mapView.setVisibleMapRect(mapRect.boundingMapRect, edgePadding: NSEdgeInsets(top: 50.0,left: 50.0,bottom: 50.0,right: 50.0), animated: true)

            polyLineRenderer.strokeColor = NSColor.blue
            polyLineRenderer.lineWidth = 3.0

            return polyLineRenderer
        }


        return MKPolylineRenderer()
    }
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation is MKUserLocation {
            return nil;
        }
        if annotation === currentAnnotation {
            currentAnnotationView = MKAnnotationView()
            currentAnnotationView.image = NSImage(named: NSImage.Name("target")) 
            return currentAnnotationView
        }
        return nil
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
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        
        let table = notification.object as! NSTableView

        if let suggestion = completerResults?[table.selectedRow] {
            // Each suggestion is a MKLocalSearchCompletion with a title, subtitle, and ranges describing what part of the title
            // and subtitle matched the current query string. The ranges can be used to apply helpful highlighting of the text in
            // the completion suggestion that matches the current query fragment.
            lookupAndAddPlacemark(suggestion.title)
        }
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
