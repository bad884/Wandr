//
//  SlideUpView.swift
//  TravelApp
//
//  Created by Richard Wollack on 4/12/17.
//  Copyright © 2017 Scott Franklin. All rights reserved.
//

import UIKit 

struct SlideUpViewOrigins {
    let wayDown = CGPoint(x: 12.5, y: UIScreen.main.bounds.height - 35)
    let middle = CGPoint(x: 0.0, y: UIScreen.main.bounds.height - (UIScreen.main.bounds.size.width / 3) - 10)
    let wayUp = CGPoint(x: 0.0, y: 75)
    let defaultSize = CGSize(width: UIScreen.main.bounds.width - 25, height: UIScreen.main.bounds.height - 75)
    let shiftedSize = CGSize(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height - 75)
}

enum NearbyScrollStatus {
    case idle
    case scrolling
    case neverScrolled
}

class SlideUpView: UIVisualEffectView {
    var centerPath: IndexPath?
    let origins = SlideUpViewOrigins()
    var currentOrigin: CGPoint!
    var wayDownLabel = UILabel(frame: CGRect(x: 15, y: 5, width: 100, height: 20))
    var collectionView: UICollectionView!
    var tableView: UITableView!
    var collectionViewScrollStatus: NearbyScrollStatus = .neverScrolled
    
    private var panGesture: UIPanGestureRecognizer!
    
    override init(effect: UIVisualEffect?) {
        super.init(effect: effect)
        
        let labelFont = UIFont(name: "Avenir", size: 14)
        
        setupPanGesture()
        
        frame = CGRect(origin: origins.wayDown, size: origins.defaultSize)
        currentOrigin = frame.origin
        layer.cornerRadius = 5.0
        clipsToBounds = true
        
        wayDownLabel.font = labelFont
        wayDownLabel.text = "Nearby Places"
        wayDownLabel.textColor = .white
        
        addSubview(wayDownLabel)
        setupCollectionView()
        setupTableView()
        registerNotifications()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    func registerNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateNearbyPlaces(notification:)),
            name: Notification.Name(rawValue: "ReceivedNewNearbyPlaces"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updatePopularPlaces(notification:)),
            name: Notification.Name(rawValue: "ReceivedNewPopularPlaces"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(photosDidUpdate(notification:)),
            name: Notification.Name(rawValue: "AddedNewPhoto"),
            object: nil
        )
    }
    
    func updateNearbyPlaces(notification: Notification) {
        collectionViewScrollStatus = .neverScrolled
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        collectionView.scrollToItem(
            at: IndexPath(row: 0, section: 0),
            at: .centeredHorizontally,
            animated: true
        )
    }
    
    func updatePopularPlaces(notification: Notification) {
        tableView.reloadData()
    }
    
    func photosDidUpdate(notification: Notification) {
        collectionView.reloadData()
    }
    
    func setupCollectionView() {
        let layout:NearbyCollectionViewFlowLayout = NearbyCollectionViewFlowLayout()
        let collectionViewFrame = CGRect(x: 0, y: 10, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.size.width / 3)
        
        layout.scrollDirection = .horizontal
        
        collectionView = UICollectionView(frame: collectionViewFrame, collectionViewLayout: layout)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(UINib(nibName: "SlideUpCollectionViewCell", bundle: .main), forCellWithReuseIdentifier: "slideCollectionCell")
        collectionView.backgroundColor = .clear
        collectionView.isHidden = true
        collectionView.isPagingEnabled = false
        collectionView.decelerationRate = UIScrollViewDecelerationRateFast
        
        addSubview(collectionView)
    }
    
    func setupTableView() {
        let tableViewFrame = CGRect(x: 0, y: 150, width: UIScreen.main.bounds.size.width, height: frame.height)
        
        tableView = UITableView(frame: tableViewFrame, style: .plain)
        tableView.isUserInteractionEnabled = true
        tableView.register(UINib(nibName: "PopularTableViewCell", bundle: .main), forCellReuseIdentifier: "popularTableCell")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.isHidden = true
        tableView.backgroundColor = .clear
        
        addSubview(tableView)
    }
    
    func setupPanGesture() {
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(dragRecognizer(gesture:)))
        addGestureRecognizer(panGesture)
    }
    
    func dragRecognizer(gesture: UIPanGestureRecognizer) {
        let velocity = gesture.velocity(in: gesture.view)
        
        if gesture.state == .began {
            checkPanDirection(velocity: velocity)
        }
    }
    
    func checkPanDirection(velocity: CGPoint) {
        if fabs(velocity.y) > fabs(velocity.x) {
            if velocity.y > 0 {
                didDragDown()
            } else {
                didDragUp()
            }
        }
    }
    
    func didDragUp() {
        switch currentOrigin {
        case origins.wayDown:
            animateMiddle()
            break
        case origins.middle:
            animateWayUp()
            break
        default:
            break
        }
    }
    
    func didDragDown() {
        switch currentOrigin {
        case origins.wayUp:
            animateMiddle()
            break
        case origins.middle:
            animateWayDown()
        default:
            break
        }
    }
    
    func animateMiddle() {
        UIView.animate(withDuration: 0.5, delay: 0.1, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.0, options: .curveEaseOut, animations: {
            self.frame = CGRect(origin: self.origins.middle, size: self.origins.shiftedSize)
            self.currentOrigin = self.origins.middle
            self.layer.cornerRadius = 0.0
            self.collectionView.isHidden = false
            self.tableView.frame.origin.y = 150
            self.wayDownLabel.isHidden = true
        }, completion: { _ in
            
        })
    }
    
    func animateWayUp(completion: ((Bool) -> Void)? = nil) {
        UIView.animate(withDuration: 0.5, delay: 0.1, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.0, options: .curveEaseOut, animations: {
            self.frame = CGRect(origin: self.origins.wayUp, size: self.origins.shiftedSize)
            self.currentOrigin = self.origins.wayUp
            self.layer.cornerRadius = 0.0
            self.collectionView.isHidden = true
            self.tableView.frame.origin.y = 0.0
            self.tableView.isHidden = false
            self.wayDownLabel.isHidden = true
        }, completion: nil)
    }
    
    func animateWayDown() {
        UIView.animate(withDuration: 0.5, delay: 0.1, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.0, options: .curveEaseOut, animations: {
            self.frame = CGRect(origin: self.origins.wayDown, size: self.origins.defaultSize)
            self.currentOrigin = self.origins.wayDown
            self.layer.cornerRadius = 5.0
            self.collectionView.isHidden = true
            self.wayDownLabel.isHidden = false
        }, completion: nil)
    }
}

extension SlideUpView: UICollectionViewDelegateFlowLayout, UICollectionViewDelegate, UICollectionViewDataSource {
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return PlaceStore.shared.nearbyPlaces.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "slideCollectionCell", for: indexPath) as! SlideUpCollectionViewCell
        let placeData = PlaceStore.shared.nearbyPlaces[indexPath.row]
        let photo = PlaceStore.shared.getPhoto(for: placeData["place_id"] as! String)
        
        cell.titleLabel.text = placeData["name"] as? String
        
        if photo.status == .downloaded {
            cell.imageView.image = photo.image
        } else {
            cell.imageView.image = #imageLiteral(resourceName: "Placeholder_location.png")
        }
        
        if collectionViewScrollStatus == .idle && centerPath?.row == indexPath.row {
            cell.imageView.alpha = 1.0
        } else {
            cell.imageView.alpha = 0.6
        }
        
        if collectionViewScrollStatus == .neverScrolled && indexPath.row == 0 {
            cell.imageView.alpha = 1.0
        }
        
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = UIScreen.main.bounds.size.width / 3
        
        return CGSize(width: width, height: width)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        return 0.0
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return 0.0
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        let width = UIScreen.main.bounds.width / 3
        return UIEdgeInsets(top: 0.0, left: width, bottom: 0.0, right: width)
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let centerPoint = CGPoint(
            x: collectionView.center.x + collectionView.contentOffset.x,
            y: collectionView.center.y + collectionView.contentOffset.y
        )
        
        if let centerIndexPath = collectionView.indexPathForItem(at: centerPoint) {
            let paths = collectionView.indexPathsForVisibleItems
            
            for path in paths {
                let cell = collectionView.cellForItem(at: path) as! SlideUpCollectionViewCell
                
                if path.row == centerIndexPath.row {
                    cell.imageView.alpha = 1.0
                } else {
                    cell.imageView.alpha = 0.6
                }
            }
            
            centerPath = centerIndexPath
        }
        
        collectionViewScrollStatus = .idle
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        collectionViewScrollStatus = .scrolling
        
        if centerPath != nil {
            let cell = collectionView.cellForItem(at: centerPath!) as? SlideUpCollectionViewCell
            cell?.imageView.alpha = 0.5
        }
    }
}

extension SlideUpView: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return PlaceStore.shared.popularPlaces.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "popularTableCell", for: indexPath) as! PopularTableViewCell
        
        if PlaceStore.shared.popularPlaces[indexPath.row].index(forKey: "name") != nil {
            cell.titleLabel.text = PlaceStore.shared.popularPlaces[indexPath.row]["name"] as? String
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let effect = UIBlurEffect(style: .light)
        let header = UIVisualEffectView(effect: effect)
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(dragRecognizer(gesture:)))
        
        header.frame = CGRect(x: 0, y: 0, width: tableView.frame.width, height: 50)
        header.addGestureRecognizer(panGesture)
        
        let headerLabel = UILabel(frame: CGRect(x: 20, y: 0, width: header.frame.width - 20, height: header.frame.height))
        
        headerLabel.text = "Popular"
        headerLabel.font = UIFont(name: "Helectiva", size: 18)
        headerLabel.textColor = .white
        headerLabel.text = "Popular"
        
        header.addSubview(headerLabel)
        
        return header
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 50
    }
}
