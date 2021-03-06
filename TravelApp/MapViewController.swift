//
//  MapViewController.swift
//  TravelApp
//
//  Created by Macbook on 3/9/17.
//  Copyright © 2017 Scott Franklin. All rights reserved.
//

import UIKit
import MapKit
import CoreLocation
import GooglePlaces

enum MapPanningSource {
    case automatic
    case user
    case searchUpdate
}

class MapViewController: UIViewController, MKMapViewDelegate, LocationServiceDelegate, UIPopoverPresentationControllerDelegate
{
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    @IBAction func gotoCurrentLocation(_ sender: Any) {
        let currentLocation = locationService.locationManager?.location
        let lat = currentLocation?.coordinate.latitude
        let long = currentLocation?.coordinate.longitude
        let center = CLLocationCoordinate2D(latitude: lat!, longitude: long!)
        let region = MKCoordinateRegion(center: center, span: self.mapView.region.span)
        mapView.setRegion(region, animated: true)
        PlaceStore.shared.updateCurrentPlaces(with: center, searchRadius: 4000)
    }

    @IBOutlet weak var mapInfoButton: UIButton!
    @IBOutlet weak var settingsBlurView: UIVisualEffectView!
    
    let appDelegate = UIApplication.shared.delegate as! AppDelegate
    var searchResultViewController = GMSAutocompleteResultsViewController()
    var panningSource: MapPanningSource = .searchUpdate
    
    lazy var searchController: UISearchController = ({
        [unowned self] in
        let controller = TravelSearchController(searchResultsController: self.searchResultViewController)
        
        controller.delegate = self
        controller.searchResultsUpdater = self.searchResultViewController
        controller.dimsBackgroundDuringPresentation = false
        controller.searchBar.placeholder = "Where To?"
        
        return controller
    })()
    
    var navBarView: TravelNavBarView!
    var slideView: SlideUpView!
    var alertController: UIAlertController?
    var alertTimer: Timer?
    var remainingTime = 0
    var baseMessage: String?
    
    //store places as array of dictionaries for now...
    var currentPlaces = [Dictionary<String, AnyObject>]()
    
    @IBOutlet weak var redoSearchBlurView: UIVisualEffectView!
    @IBOutlet weak var redoSearchButton: UIButton!
    @IBOutlet weak var mapView: MKMapView! {
        didSet {
            mapView.mapType = .standard
            mapView.delegate = self
            mapView.showsUserLocation = true
        }
    }
    
    let locationService = LocationService.singleton
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.settingsBlurView.layer.cornerRadius = 10
        self.settingsBlurView.clipsToBounds = true
        self.settingsBlurView.frame.origin = CGPoint(x: 10, y: 65)
        
        definesPresentationContext = true
        
        // Zoom to current location
        locationService.startUpdatingLocation()
        let lat: CLLocationDegrees
        let long: CLLocationDegrees
        
        if let currentLocation = locationService.locationManager?.location {
            lat = currentLocation.coordinate.latitude
            long = currentLocation.coordinate.longitude
        } else {
            // default to Madison if location services are off
            lat = CLLocationDegrees(43.0731)
            long = CLLocationDegrees(-89.4012)
        }
        
        let center = CLLocationCoordinate2D(latitude: lat, longitude: long)
        
        setupSearchBar()
        
        // Add the slide up view
        slideView = SlideUpView(effect: UIBlurEffect(style: .dark))
        slideView.parentVc = self
        view.addSubview(slideView)
        
        // Register for notifications
        NotificationCenter.default.addObserver(self, selector: #selector(updatePlaces(notification:)), name: Notification.Name(rawValue: "ReceivedNewNearbyPlaces"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(nearbyFocusedPlaceChanged(notification:)), name: Notification.Name(rawValue: "NearbyFocusedPlaceChanged"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(cartItemAlreadyPresent(notification:)), name: Notification.Name(rawValue: "CartItemAlreadyPresent"), object: nil)
        
        // Configure button for searching in area
        redoSearchBlurView.layer.cornerRadius = 5.0;
        redoSearchBlurView.clipsToBounds = true
        
        panningSource = .searchUpdate
        
        PlaceStore.shared.apiSearchMode = .initial
        PlaceStore.shared.updateCurrentPlaces(with: center, searchRadius: 4000)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "showMapSettings" {
            let popoverViewController = segue.destination
            popoverViewController.popoverPresentationController?.delegate = self
            popoverViewController.modalPresentationStyle = .popover
            popoverViewController.popoverPresentationController?.sourceRect = self.mapInfoButton.bounds
        }
    }
    
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        return UIModalPresentationStyle.none
    }
    
    // Button action to redo search in current area
    @IBAction func redoSearchInAreaAction(_ sender: Any) {
        redoSearchInArea()
    }
    
    func cartItemAlreadyPresent(notification: Notification) {
        let time = 3
        
        guard (alertController == nil) else {
            return
        }
        
        baseMessage = "You already like this place"
        remainingTime = time
        
        alertController = UIAlertController(title: title, message: baseMessage, preferredStyle: .alert)
        
        let cancelAction = UIAlertAction(title: "Thanks!", style: .cancel) { (action) in
            self.alertController=nil;
            self.alertTimer?.invalidate()
            self.alertTimer=nil
        }
        
        alertController!.addAction(cancelAction)
        
        alertTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(countDown), userInfo: nil, repeats: true)
        
        self.present(alertController!, animated: true, completion: nil)
    }
    
    func countDown() {
        
        self.remainingTime -= 1
        if (remainingTime < 0) {
            alertTimer?.invalidate()
            alertTimer = nil
            alertController!.dismiss(animated: true, completion: {
                self.alertController = nil
            })
        } else {
            alertController!.message = self.baseMessage
        }
        
    }
    
    func redoSearchInArea() {
        let span = mapView.region.span
        let center = mapView.region.center
        let loc1 = CLLocation(latitude: center.latitude - span.latitudeDelta * 0.5, longitude: center.longitude)
        let loc2 = CLLocation(latitude: center.latitude + span.latitudeDelta * 0.5, longitude: center.longitude)
        let metersInLatitude = loc1.distance(from: loc2)
        
        PlaceStore.shared.apiSearchMode = .initial
        PlaceStore.shared.updateCurrentPlaces(with: center, searchRadius: Int(metersInLatitude / 2))
        redoSearchBlurView.isHidden = true;
    }
    
    // Dispose of any resources that can be recreated
    override func didReceiveMemoryWarning()
    {
        super.didReceiveMemoryWarning()
    }    
    
    //# MARK: - LocationService delegate methods
    func tracingLocation(currentLocation: CLLocation) {}
    func tracingLocationDidFailWithError(error: NSError) {}
    
    //# MARK: - MapView delegate methods
    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        switch panningSource {
        case .user:
            redoSearchBlurView.isHidden = false
            break
        case .automatic:
            let currentPlaceId = PlaceStore.shared.getCurrentFocusedPlace()["place_id"] as? String
            
            panningSource = .user
            redoSearchBlurView.isHidden = true
            
            // Show annotation call out
            for annotation in mapView.annotations {
                if let annotation = annotation as? PlaceMapAnnotation {
                    if annotation.placeId  == currentPlaceId {
                        mapView.selectAnnotation(annotation, animated: true)
                        break
                    }
                }
            }
            break
        case .searchUpdate:
            panningSource = .user
            break
        }
    }
    
//    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
//        let annotationView = PlaceAnnotationView()
//        
//        return annotationView
//    }
    
    
    func addAnnotations() {
        // Add place annotations to map
        for place in PlaceStore.shared.nearbyPlaces {
            let placeLoc = place["geometry"]!["location"] as! Dictionary<String, AnyObject>
            let location:CLLocationCoordinate2D = CLLocationCoordinate2DMake(placeLoc["lat"] as! CLLocationDegrees, placeLoc["lng"] as! CLLocationDegrees)
            let annotation = PlaceMapAnnotation(myCoordinate: location, title: (place["name"] as? String)!)
//            annotation.coordinate = location
            annotation.placeId = place["place_id"] as? String
            mapView.addAnnotation(annotation)
        }
    }
    
    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        var counter = 0;
//        let placeAnnotationView = view as! PlaceAnnotationView
        let annotation = view.annotation as! PlaceMapAnnotation
        for place in PlaceStore.shared.nearbyPlaces {
            if place["place_id"] as? String == (annotation.placeId)! {
                slideView.animateMiddle()
                slideView.collectionViewScrollStatus = .scrolling
                slideView.collectionView.scrollToItem(
                    at: IndexPath(row: counter, section: 0),
                    at: .centeredHorizontally,
                    animated: true
                )
            } else {
                counter += 1
            }
        }
    }
    
    //# MARK: - Methods for navigation to tag and cart views
    func transitionToPreferenceView() {
        let storyboard = UIStoryboard(name: "Tag", bundle: .main)
        let vc = storyboard.instantiateInitialViewController()
        present(vc!, animated: true, completion: nil)
    }
    
    func transitionToCartView() {
        let storyboard = UIStoryboard(name: "Cart", bundle: nil)
        let vc = storyboard.instantiateViewController(withIdentifier: "CartVC") as! CartViewController
        let nc = UINavigationController(rootViewController: vc)
        vc.modalPresentationStyle = .overCurrentContext
        nc.modalPresentationStyle = .overCurrentContext
        present(nc, animated: true, completion: nil)
    }
    
    // Set up the top search bar
    func setupSearchBar() {
        let filter = GMSAutocompleteFilter()
        filter.type = .city
        
        searchResultViewController.autocompleteFilter = filter
        searchResultViewController.delegate = self
        navBarView = TravelNavBarView(
            frame: CGRect(x: 10, y: 10.0, width: UIScreen.main.bounds.size.width - 20, height: 45.0),
            searchBar: searchController.searchBar,
            navHandler: self,
            preferenceSelector: #selector(transitionToPreferenceView),
            cartSelector: #selector(transitionToCartView)
        )
        searchController.searchBar.delegate = navBarView
        
        view.addSubview(navBarView)
    }
    
    //# MARK: - Selectors for responding to NotificationCenter
    
    // Changes the focus of the map when scrolling through the CollectionView
    func nearbyFocusedPlaceChanged(notification: Notification) {
        let selectedIndex = PlaceStore.shared.currentNearbyFocusedPlaceIndex
        
        if selectedIndex < PlaceStore.shared.nearbyPlaces.count {
            let placeLoc = PlaceStore.shared.nearbyPlaces[selectedIndex]["geometry"]!["location"] as! Dictionary<String, AnyObject>
            let location:CLLocationCoordinate2D = CLLocationCoordinate2DMake(placeLoc["lat"] as! CLLocationDegrees, placeLoc["lng"] as! CLLocationDegrees)
            let span = MKCoordinateSpanMake(0.025, 0.025)
            let region = MKCoordinateRegion(center: location, span: span)
            
            mapView.setRegion(region, animated: true)
            panningSource = .automatic
        }
    }
    
    // Called after nearby places have been updated
    func updatePlaces(notification: Notification) {
        let span = MKCoordinateSpanMake(0.075, 0.075)
        let region = MKCoordinateRegion(center: PlaceStore.shared.currentSearchCoordinate!, span: span)
        
        
        currentPlaces = PlaceStore.shared.nearbyPlaces
        mapView.removeAnnotations(mapView.annotations)
        redoSearchBlurView.isHidden = true
        panningSource = .searchUpdate
        mapView.setRegion(region, animated: true)
        addAnnotations()
    }
    
    // Transitions to Swipe View with selected index of popular table
    func transitionToSwipeView(index: Int, dataType: SwipeViewDataType) {
        let storyboard: UIStoryboard = UIStoryboard(name: "CardSwipe", bundle: nil)
        let vc: UINavigationController = storyboard.instantiateViewController(withIdentifier: "SwipeNavigationView") as! UINavigationController
        if let cardView = vc.viewControllers.first as? CardSwipeController {
            cardView.placeIndex = index
            cardView.dataType = dataType
        }
        self.present(vc, animated: true, completion: nil)
    }
    
    // Transitions to Swipe View with selected index of popular table
    func transitionToSwipeView() {
        let storyboard: UIStoryboard = UIStoryboard(name: "CardSwipe", bundle: nil)
        let vc: UINavigationController = storyboard.instantiateViewController(withIdentifier: "SwipeNavigationView") as! UINavigationController
        if let cardView = vc.viewControllers.first as? CardSwipeController {
            cardView.placeIndex = 0
            cardView.dataType = .popular
        }
        self.present(vc, animated: true, completion: nil)
    }
}

//# MARK: - UISearchResultsUpdating methods

extension MapViewController: GMSAutocompleteResultsViewControllerDelegate {
    func resultsController(_ resultsController: GMSAutocompleteResultsViewController,
                           didAutocompleteWith place: GMSPlace) {
        searchController.dismiss(animated: true, completion: {
            self.navBarView.transitionToOrignialState()
            self.navBarView.searchBar.searchTextField.text = place.formattedAddress
        })
        
        // Update map to focus on searched location
        let coordinateRegion = MKCoordinateRegionMakeWithDistance(place.coordinate, 5000, 5000)
        mapView.setRegion(coordinateRegion, animated: true)
        
        //starts the request for places nearby the selected location
        PlaceStore.shared.apiSearchMode = .initial
        PlaceStore.shared.updateCurrentPlaces(with: place.coordinate, searchRadius: 4000)
    }
    
    func resultsController(_ resultsController: GMSAutocompleteResultsViewController,
                           didFailAutocompleteWithError error: Error){
        // TODO: handle the error.
        print("Error: ", error.localizedDescription)
    }
    
    // Turn the network activity indicator on and off again.
    func didRequestAutocompletePredictions(forResultsController resultsController: GMSAutocompleteResultsViewController) {
        UIApplication.shared.isNetworkActivityIndicatorVisible = true
    }
    
    func didUpdateAutocompletePredictions(forResultsController resultsController: GMSAutocompleteResultsViewController) {
        UIApplication.shared.isNetworkActivityIndicatorVisible = false
    }
}

//# MARK: - UISearchControllerDelegate methods

extension MapViewController: UISearchControllerDelegate {
    func didDismissSearchController(_ searchController: UISearchController) {
        searchController.searchBar.frame = navBarView.originalSearchBarFrame
    }
}

//# MARK: - MKMapView extension

extension MKMapView {
    override open func layoutSubviews() {
        super.layoutSubviews()
        
        //reposition the compass so it's not under the search bar
        let compassView = self.value(forKey: "compassView") as! UIView
        compassView.frame = CGRect(x: compassView.frame.origin.x, y: 85, width: 36, height: 36)
    }
}
