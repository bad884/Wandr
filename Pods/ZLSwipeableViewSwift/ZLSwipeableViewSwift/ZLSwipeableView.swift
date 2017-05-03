//
//  ZLSwipeableView.swift
//  ZLSwipeableViewSwiftDemo
//
//  Created by Zhixuan Lai on 4/27/15.
//  Copyright (c) 2015 Zhixuan Lai. All rights reserved.
//

import UIKit

// data source
public typealias NextViewHandler = () -> UIView?
public typealias PreviousViewHandler = () -> UIView?

// customization
public typealias AnimateViewHandler = (_ view: UIView, _ index: Int, _ views: [UIView], _ swipeableView: ZLSwipeableView) -> ()
public typealias InterpretDirectionHandler = (_ topView: UIView, _ direction: Direction, _ views: [UIView], _ swipeableView: ZLSwipeableView) -> (CGPoint, CGVector)
public typealias ShouldSwipeHandler = (_ view: UIView, _ movement: Movement, _ swipeableView: ZLSwipeableView) -> Bool

// delegates
public typealias DidStartHandler = (_ view: UIView, _ atLocation: CGPoint) -> ()
public typealias SwipingHandler = (_ view: UIView, _ atLocation: CGPoint, _ translation: CGPoint) -> ()
public typealias DidEndHandler = (_ view: UIView, _ atLocation: CGPoint) -> ()
public typealias DidSwipeHandler = (_ view: UIView, _ inDirection: Direction, _ directionVector: CGVector) -> ()
public typealias DidCancelHandler = (_ view: UIView) -> ()
public typealias DidTap = (_ view: UIView, _ atLocation: CGPoint) -> ()
public typealias DidDisappear = (_ view: UIView) -> ()

public struct Movement {
    let location: CGPoint
    let translation: CGPoint
    let velocity: CGPoint
}

// MARK: - Main
public class ZLSwipeableView: UIView {
    
    // MARK: Data Source
    public var numberOfActiveView = UInt(4)
    public var nextView: NextViewHandler? {
        didSet {
            loadViews()
        }
    }
    public var previousView: PreviousViewHandler?
    // Rewinding
    public var history = [UIView]()
    public var numberOfHistoryItem = UInt(10)
    
    // MARK: Customizable behavior
    public var animateView = ZLSwipeableView.defaultAnimateViewHandler()
    public var interpretDirection = ZLSwipeableView.defaultInterpretDirectionHandler()
    public var shouldSwipeView = ZLSwipeableView.defaultShouldSwipeViewHandler()
    public var minTranslationInPercent = CGFloat(0.25)
    public var minVelocityInPointPerSecond = CGFloat(750)
    public var allowedDirection = Direction.Horizontal
    public var onlySwipeTopCard = false
    
    // MARK: Delegate
    public var didStart: DidStartHandler?
    public var swiping: SwipingHandler?
    public var didEnd: DidEndHandler?
    public var didSwipe: DidSwipeHandler?
    public var didCancel: DidCancelHandler?
    public var didTap: DidTap?
    public var didDisappear: DidDisappear?
    
    // MARK: Private properties
    /// Contains subviews added by the user.
    private var containerView = UIView()
    
    /// Contains auxiliary subviews.
    private var miscContainerView = UIView()
    
    private var animator: UIDynamicAnimator!
    
    private var viewManagers = [UIView: ViewManager]()
    
    private var scheduler = Scheduler()
    
    // MARK: Life cycle
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }
    
    private func setup() {
        addSubview(containerView)
        addSubview(miscContainerView)
        animator = UIDynamicAnimator(referenceView: self)
    }
    
    deinit {
        nextView = nil
        
        didStart = nil
        swiping = nil
        didEnd = nil
        didSwipe = nil
        didCancel = nil
        didDisappear = nil
    }
    
    override public func layoutSubviews() {
        super.layoutSubviews()
        containerView.frame = bounds
    }
    
    // MARK: Public APIs
    public func topView() -> UIView? {
        return activeViews().first
    }
    
    // top view first
    public func activeViews() -> [UIView] {
        return allViews().filter() {
            view in
            guard let viewManager = viewManagers[view] else { return false }
            if case .Swiping(_) = viewManager.state {
                return false
            }
            return true
            }.reversed()
    }
    
    public func loadViews() {
        for _ in UInt(activeViews().count) ..< numberOfActiveView {
            if let nextView = nextView?() {
                insert(view: nextView, atIndex: 0)
            }
        }
        updateViews()
    }
    
    public func rewind() {
        var viewToBeRewinded: UIView?
        if let lastSwipedView = history.popLast() {
            viewToBeRewinded = lastSwipedView
        } else if let view = previousView?() {
            viewToBeRewinded = view
        }
        
        guard let view = viewToBeRewinded else { return }
        
        insert(view: view, atIndex: allViews().count)
        updateViews()
    }
    
    public func discardViews() {
        for view in allViews() {
            remove(view: view)
        }
    }
    
    public func swipeTopView(inDirection direction: Direction) {
        guard let topView = topView() else { return }
        let (location, directionVector) = interpretDirection(topView, direction, activeViews(), self)
        swipeTopView(fromPoint: location, inDirection: directionVector)
    }
    
    public func swipeTopView(fromPoint location: CGPoint, inDirection directionVector: CGVector) {
        guard let topView = topView(), let topViewManager = viewManagers[topView] else { return }
        topViewManager.state = .Swiping(location, directionVector)
        swipeView(view: topView, location: location, directionVector: directionVector)
    }
    
    // MARK: Private APIs
    private func allViews() -> [UIView] {
        return containerView.subviews
    }
    
    private func insert(view: UIView, atIndex index: Int) {
        guard !allViews().contains(view) else {
            // this view has been schedule to be removed
            guard let viewManager = viewManagers[view] else { return }
            viewManager.state = viewManager.snappingStateAtContainerCenter()
            return
        }
        
        let viewManager = ViewManager(view: view, containerView: containerView, index: index, miscContainerView: miscContainerView, animator: animator, swipeableView: self)
        viewManagers[view] = viewManager
    }
    
    private func remove(view: UIView) {
        guard allViews().contains(view) else { return }
        
        viewManagers.removeValue(forKey: view)
        self.didDisappear?(view)
    }
    
    public func updateViews() {
        let activeViews = self.activeViews()
        let inactiveViews = allViews().arrayByRemoveObjectsInArray(array: activeViews)
        
        for view in inactiveViews {
            view.isUserInteractionEnabled = false
        }
        
        guard let gestureRecognizers = activeViews.first?.gestureRecognizers, gestureRecognizers.filter({ gestureRecognizer in gestureRecognizer.state != .possible }).count == 0 else { return }
        
        for i in 0 ..< activeViews.count {
            let view = activeViews[i]
            view.isUserInteractionEnabled = onlySwipeTopCard ? i == 0 : true
            let shouldBeHidden = i >= Int(numberOfActiveView)
            view.isHidden = shouldBeHidden
            guard !shouldBeHidden else { continue }
            animateView(view, i, activeViews, self)
        }
    }
    
    func swipeView(view: UIView, location: CGPoint, directionVector: CGVector) {
        let direction = Direction.fromPoint(point: CGPoint(x: directionVector.dx, y: directionVector.dy))
        
        scheduleToBeRemoved(view: view) { aView in
            !self.containerView.convert(aView.frame, to: nil).intersects(UIScreen.main.bounds)
        }
        didSwipe?(view, direction, directionVector)
        loadViews()
    }
    
    func scheduleToBeRemoved(view: UIView, withPredicate predicate: @escaping (UIView) -> Bool) {
        guard allViews().contains(view) else { return }
        
        history.append(view)
        if UInt(history.count) > numberOfHistoryItem {
            history.removeFirst()
        }
        scheduler.scheduleRepeatedly(action: { () -> Void in
            self.allViews().arrayByRemoveObjectsInArray(array: self.activeViews()).filter({ view in predicate(view) }).forEach({ view in self.remove(view: view) })
        }, interval: 0.3) { () -> Bool in
            return self.activeViews().count == self.allViews().count
        }
    }
    
}

// MARK: - Default behaviors
extension ZLSwipeableView {
    
    static func defaultAnimateViewHandler() -> AnimateViewHandler {
        func toRadian(degree: CGFloat) -> CGFloat {
            return degree * CGFloat(M_PI / 180)
        }
        
        func rotateView(view: UIView, forDegree degree: CGFloat, duration: TimeInterval, offsetFromCenter offset: CGPoint, swipeableView: ZLSwipeableView,  completion: ((Bool) -> Void)? = nil) {
            UIView.animate(withDuration: duration, delay: 0, options: .allowUserInteraction, animations: {
                view.center = swipeableView.convert(swipeableView.center, from: swipeableView.superview)
                var transform = CGAffineTransform(translationX: offset.x, y: offset.y)
                transform = transform.rotated(by: toRadian(degree: degree))
                transform = transform.translatedBy(x: -offset.x, y: -offset.y)
                view.transform = transform
            },
                           completion: completion)
        }
        
        return { (view: UIView, index: Int, views: [UIView], swipeableView: ZLSwipeableView) in
            let degree = CGFloat(1)
            let duration = 0.4
            let offset = CGPoint(x: 0, y: swipeableView.bounds.height * 0.3)
            switch index {
            case 0:
                rotateView(view: view, forDegree: 0, duration: duration, offsetFromCenter: offset, swipeableView: swipeableView)
            case 1:
                rotateView(view: view, forDegree: degree, duration: duration, offsetFromCenter: offset, swipeableView: swipeableView)
            case 2:
                rotateView(view: view, forDegree: -degree, duration: duration, offsetFromCenter: offset, swipeableView: swipeableView)
            default:
                rotateView(view: view, forDegree: 0, duration: duration, offsetFromCenter: offset, swipeableView: swipeableView)
            }
        }
    }
    
    static func defaultInterpretDirectionHandler() -> InterpretDirectionHandler {
        return { (topView: UIView, direction: Direction, views: [UIView], swipeableView: ZLSwipeableView) in
            let programmaticSwipeVelocity = CGFloat(1000)
            let location = CGPoint(x: topView.center.x, y: topView.center.y*0.7)
            var directionVector: CGVector!
            
            switch direction {
            case Direction.Left:
                directionVector = CGVector(dx: -programmaticSwipeVelocity, dy: 0)
            case Direction.Right:
                directionVector = CGVector(dx: programmaticSwipeVelocity, dy: 0)
            case Direction.Up:
                directionVector = CGVector(dx: 0, dy: -programmaticSwipeVelocity)
            case Direction.Down:
                directionVector = CGVector(dx: 0, dy: programmaticSwipeVelocity)
            default:
                directionVector = CGVector(dx: 0, dy: 0)
            }
            
            return (location, directionVector)
        }
    }
    
    static func defaultShouldSwipeViewHandler() -> ShouldSwipeHandler {
        return { (view: UIView, movement: Movement, swipeableView: ZLSwipeableView) -> Bool in
            let translation = movement.translation
            let velocity = movement.velocity
            let bounds = swipeableView.bounds
            let minTranslationInPercent = swipeableView.minTranslationInPercent
            let minVelocityInPointPerSecond = swipeableView.minVelocityInPointPerSecond
            let allowedDirection = swipeableView.allowedDirection
            
            func areTranslationAndVelocityInTheSameDirection() -> Bool {
                return CGPoint.areInSameTheDirection(p1: translation, p2: velocity)
            }
            
            func isDirectionAllowed() -> Bool {
                return Direction.fromPoint(point: translation).intersection(allowedDirection) != .None
            }
            
            func isTranslationLargeEnough() -> Bool {
                return abs(translation.x) > minTranslationInPercent * bounds.width || abs(translation.y) > minTranslationInPercent * bounds.height
            }
            
            func isVelocityLargeEnough() -> Bool {
                return velocity.magnitude > minVelocityInPointPerSecond
            }
            
            return isDirectionAllowed() && areTranslationAndVelocityInTheSameDirection() && (isTranslationLargeEnough() || isVelocityLargeEnough())
        }
    }
    
}

// MARK: - Deprecated APIs
extension ZLSwipeableView {
    
    @available(*, deprecated: 1, message: "Use numberOfActiveView")
    public var numPrefetchedViews: UInt {
        get {
            return numberOfActiveView
        }
        set(newValue){
            numberOfActiveView = newValue
        }
    }
    
    @available(*, deprecated: 1, message: "Use allowedDirection")
    public var direction: Direction {
        get {
            return allowedDirection
        }
        set(newValue){
            allowedDirection = newValue
        }
    }
    
    @available(*, deprecated: 1, message: "Use minTranslationInPercent")
    public var translationThreshold: CGFloat {
        get {
            return minTranslationInPercent
        }
        set(newValue){
            minTranslationInPercent = newValue
        }
    }
    
    @available(*, deprecated: 1, message: "Use minVelocityInPointPerSecond")
    public var velocityThreshold: CGFloat {
        get {
            return minVelocityInPointPerSecond
        }
        set(newValue){
            minVelocityInPointPerSecond = newValue
        }
    }
    
}

// MARK: - Helper extensions
public func *(lhs: CGPoint, rhs: CGFloat) -> CGPoint {
    return CGPoint(x: lhs.x * rhs, y: lhs.y * rhs)
}

extension CGPoint {
    
    init(vector: CGVector) {
        self.init(x: vector.dx, y: vector.dy)
    }
    
    var normalized: CGPoint {
        return CGPoint(x: x / magnitude, y: y / magnitude)
    }
    
    var magnitude: CGFloat {
        return CGFloat(sqrtf(powf(Float(x), 2) + powf(Float(y), 2)))
    }
    
    static func areInSameTheDirection(p1: CGPoint, p2: CGPoint) -> Bool {
        
        func signNum(n: CGFloat) -> Int {
            return (n < 0.0) ? -1 : (n > 0.0) ? +1 : 0
        }
        
        return signNum(n: p1.x) == signNum(n: p2.x) && signNum(n: p1.y) == signNum(n: p2.y)
    }
    
}

extension CGVector {
    
    init(point: CGPoint) {
        self.init(dx: point.x, dy: point.y)
    }
    
}

extension Array where Element: Equatable {
    
    func arrayByRemoveObjectsInArray(array: [Element]) -> [Element] {
        return Array(self).filter() { element in !array.contains(element) }
    }
    
}