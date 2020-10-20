//
//  TouchDrawView.swift
//  TouchDraw
//
//  Created by Christian Paul Dehli
//

import Foundation
import UIKit

/// The protocol which the container of TouchDrawView can conform to
@objc public protocol TouchDrawViewDelegate {
    /// triggered when undo is enabled (only if it was previously disabled)
    @objc optional func undoEnabled()

    /// triggered when undo is disabled (only if it previously enabled)
    @objc optional func undoDisabled()

    /// triggered when redo is enabled (only if it was previously disabled)
    @objc optional func redoEnabled()

    /// triggered when redo is disabled (only if it previously enabled)
    @objc optional func redoDisabled()

    /// triggered when clear is enabled (only if it was previously disabled)
    @objc optional func clearEnabled()

    /// triggered when clear is disabled (only if it previously enabled)
    @objc optional func clearDisabled()
    
    /// triggered when the user finishes drawing a stroke
    @objc optional func didFinishDrawing()
}

/// A subclass of UIView which allows you to draw on the view using your fingers
open class TouchDrawView: UIView {

    /// Should be set in whichever class is using the TouchDrawView
    open weak var delegate: TouchDrawViewDelegate?

    /// Drawn underneath the strokes
    open var image: UIImage? {
        didSet(oldImage) { redrawStack() }
    }

    /// Used to register undo and redo actions
    fileprivate var touchDrawUndoManager = UndoManager()

    /// Used to keep track of all the strokes
    internal var stack: [Stroke] = []

    /// Used to keep track of the current StrokeSettings
    fileprivate let settings = StrokeSettings()

    /// This is used to render a user's strokes
    fileprivate let imageView = UIImageView()

    /// Initializes a TouchDrawView instance
    override public init(frame: CGRect) {
        super.init(frame: frame)
        initialize(frame)
    }

    /// Initializes a TouchDrawView instance
    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        initialize(CGRect.zero)
    }

    /// Adds the subviews and initializes stack
    private func initialize(_ frame: CGRect) {
        addSubview(imageView)
        draw(frame)
    }

    /// Sets the frames of the subviews
    override open func draw(_ rect: CGRect) {
        imageView.frame = rect
    }

    /// Imports the stack so that previously exported stack can be used
    open func importStack(_ stack: [Stroke]) {
        // Make sure undo is disabled
        if touchDrawUndoManager.canUndo {
            delegate?.undoDisabled?()
        }

        // Make sure that redo is disabled
        if touchDrawUndoManager.canRedo {
            delegate?.redoDisabled?()
        }

        // Make sure that clear is enabled
        if self.stack.count == 0 && stack.count > 0 {
            delegate?.clearEnabled?()
        }

        self.stack = stack
        redrawStack()
        touchDrawUndoManager.removeAllActions()
    }

    /// Used to export the current stack (each individual stroke)
    open func exportStack() -> [Stroke] {
        return stack
    }

    /// Exports the current drawing
    open func exportDrawing() -> UIImage {
        UIGraphicsBeginImageContextWithOptions(imageView.bounds.size, false, 0.0)
        imageView.image?.draw(in: imageView.bounds)

        let imageFromContext = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return imageFromContext!
    }
    
    open func exportStackAsImage(withOriginalMask mask: UIImage?) -> UIImage {
        print("exportingStackAsImage, input size: \(imageView.bounds.size)")
        var scale: CGFloat = 4.0
        if let width = mask?.size.width, width > scale*imageView.bounds.size.width {
            scale = CGFloat(Int(width/imageView.bounds.size.width))
        }
        let scaledSize = CGSize(width: imageView.bounds.size.width*scale, height: imageView.bounds.size.height*scale)
        UIGraphicsBeginImageContextWithOptions(scaledSize, false, 1.0)
        
        if let mask = mask {
            mask.draw(in: CGRect(origin: .zero, size: scaledSize))
        }
                
        for stroke in stack {
            drawStroke(stroke, scale: scale)
        }
        let imageFromContext = UIGraphicsGetImageFromCurrentImageContext()
        
        print("exportingStackAsImage, result size: \(imageFromContext!.size)")
        UIGraphicsEndImageContext()
        return imageFromContext!
    }

    /// Clears the drawing
    @objc open func clearDrawing() {
        if !touchDrawUndoManager.canUndo {
            delegate?.undoEnabled?()
        }

        if touchDrawUndoManager.canRedo {
            delegate?.redoDisabled?()
        }

        if stack.count > 0 {
            delegate?.clearDisabled?()
        }

        touchDrawUndoManager.registerUndo(withTarget: self, selector: #selector(pushAll(_:)), object: stack)
        stack = []
        redrawStack()
    }
    
    /// Reset the drawing and removes all strokes
    @objc open func resetDrawing() {
        touchDrawUndoManager.removeAllActions()
        stack = []
        redrawStack()
        
        delegate?.undoDisabled?()
        delegate?.redoDisabled?()
        delegate?.clearDisabled?()
    }

    /// Sets the brush's color
    open func setColor(_ color: UIColor?) {
        if color == nil {
            settings.color = nil
        } else {
            settings.color = CIColor(color: color!)
        }
    }

    /// Sets the brush's width
    open func setWidth(_ width: CGFloat) {
        settings.width = width
    }

    /// If possible, it will redo the last undone stroke
    open func redo() {
        if touchDrawUndoManager.canRedo {
            let stackCount = stack.count

            if !touchDrawUndoManager.canUndo {
                delegate?.undoEnabled?()
            }

            touchDrawUndoManager.redo()

            if !touchDrawUndoManager.canRedo {
                self.delegate?.redoDisabled?()
            }

            updateClear(oldStackCount: stackCount)
        }
    }

    /// If possible, it will undo the last stroke
    open func undo() {
        if touchDrawUndoManager.canUndo {
            let stackCount = stack.count

            if !touchDrawUndoManager.canRedo {
                delegate?.redoEnabled?()
            }

            touchDrawUndoManager.undo()

            if !touchDrawUndoManager.canUndo {
                delegate?.undoDisabled?()
            }

            updateClear(oldStackCount: stackCount)
        }
    }

    /// Update clear after either undo or redo
    internal func updateClear(oldStackCount: Int) {
        if oldStackCount > 0 && stack.count == 0 {
            delegate?.clearDisabled?()
        } else if oldStackCount == 0 && stack.count > 0 {
            delegate?.clearEnabled?()
        }
    }

    /// Removes the last Stroke from stack
    @objc internal func popDrawing() {
        touchDrawUndoManager.registerUndo(withTarget: self,
                                          selector: #selector(pushDrawing(_:)),
                                          object: stack.popLast())
        redrawStack()
    }

    /// Adds a new stroke to the stack
    @objc internal func pushDrawing(_ stroke: Stroke) {
        stack.append(stroke)
        drawStrokeWithContext(stroke, scale: 1.0)
        touchDrawUndoManager.registerUndo(withTarget: self, selector: #selector(popDrawing), object: nil)
    }

    /// Draws all of the strokes
    @objc internal func pushAll(_ strokes: [Stroke]) {
        stack = strokes
        redrawStack()
        touchDrawUndoManager.registerUndo(withTarget: self, selector: #selector(clearDrawing), object: nil)
    }

    open override func layoutSubviews() {
        super.layoutSubviews()
        redrawStack()
    }
}

// MARK: - Touch Actions

extension TouchDrawView {

    /// Triggered when touches begin
    override open func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first {
            let stroke = Stroke(points: [touch.location(in: self)],
                                settings: settings)
            stack.append(stroke)
        }
    }

    /// Triggered when touches move
    override open func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first {
            let stroke = stack.last!
            let lastPoint = stroke.points.last
            let currentPoint = touch.location(in: self)
            let settings = StrokeSettings(stroke.settings)
            // Set different pen color for drawing
            settings.color = CIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
            drawLineWithContext(fromPoint: lastPoint!, toPoint: currentPoint, properties: settings, scale: 1.0)
            stroke.points.append(currentPoint)
        }
    }

    /// Triggered whenever touches end, resulting in a newly created Stroke
    override open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let stroke = stack.last!
        if stroke.points.count == 1 {
            let lastPoint = stroke.points.last!
            let settings = StrokeSettings(stroke.settings)
            // Set different pen color for drawing
            settings.color = CIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
            drawLineWithContext(fromPoint: lastPoint, toPoint: lastPoint, properties: settings, scale: 1.0)
        }

        if !touchDrawUndoManager.canUndo {
            delegate?.undoEnabled?()
        }

        if touchDrawUndoManager.canRedo {
            delegate?.redoDisabled?()
        }

        if stack.count == 1 {
            delegate?.clearEnabled?()
        }

        touchDrawUndoManager.registerUndo(withTarget: self, selector: #selector(popDrawing), object: nil)
        
        delegate?.didFinishDrawing?()
    }
    
    /// Redraws the stack, which has been modified to not draw any strokes
    open func redraw() {
        self.redrawStack()
    }
    
}

// MARK: - Drawing

fileprivate extension TouchDrawView {

    /// Begins the image context
    func beginImageContext() {
        UIGraphicsBeginImageContextWithOptions(imageView.bounds.size, false, 0.0)
    }

    /// Ends image context and sets UIImage to what was on the context
    func endImageContext() {
        imageView.image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
    }

    /// Draws the current image for context
    func drawCurrentImage() {
        imageView.image?.draw(in: imageView.bounds)
    }

    /// Clears view, then draws stack
    func redrawStack() {
        beginImageContext()
        image?.draw(in: imageView.bounds)
        
        // Have changed this to _not_ draw the strokes, as we don't want them rendered
        //for stroke in stack {
        //    drawStroke(stroke)
        //}
        
        endImageContext()
    }

    /// Draws a single Stroke
    func drawStroke(_ stroke: Stroke, scale: CGFloat) {
        let properties = stroke.settings
        let points = stroke.points

        if points.count == 1 {
            let point = points[0]
            drawLine(fromPoint: point, toPoint: point, properties: properties, scale: scale)
        }

        for i in stride(from: 1, to: points.count, by: 1) {
            let point0 = points[i - 1]
            let point1 = points[i]
            drawLine(fromPoint: point0, toPoint: point1, properties: properties, scale: scale)
        }
    }

    /// Draws a single Stroke (begins/ends context
    func drawStrokeWithContext(_ stroke: Stroke, scale: CGFloat) {
        beginImageContext()
        drawCurrentImage()
        drawStroke(stroke, scale: scale)
        endImageContext()
    }

    /// Draws a line between two points
    func drawLine(fromPoint: CGPoint, toPoint: CGPoint, properties: StrokeSettings, scale: CGFloat) {
        let context = UIGraphicsGetCurrentContext()
        context!.move(to: CGPoint(x: round(fromPoint.x*scale), y: round(fromPoint.y*scale)))
        context!.addLine(to: CGPoint(x: round(toPoint.x*scale), y: round(toPoint.y*scale)))

        context!.setLineCap(CGLineCap.round)
        context!.setLineWidth(properties.width*scale)

        let color = properties.color
        if color != nil {
            context!.setStrokeColor(red: properties.color!.red,
                                    green: properties.color!.green,
                                    blue: properties.color!.blue,
                                    alpha: properties.color!.alpha)
            context!.setBlendMode(CGBlendMode.normal)
        } else {
            context!.setBlendMode(CGBlendMode.clear)
        }

        context!.strokePath()
    }

    /// Draws a line between two points (begins/ends context)
    func drawLineWithContext(fromPoint: CGPoint, toPoint: CGPoint, properties: StrokeSettings, scale: CGFloat) {
        beginImageContext()
        drawCurrentImage()
        drawLine(fromPoint: fromPoint, toPoint: toPoint, properties: properties, scale: scale)
        endImageContext()
    }
}

/// https://gist.github.com/AdamLantz/d5d841e60583e740c0b5f515ba5064fb
extension UIImage {
    public func cropImageByAlpha() -> UIImage {
        let cgImage = self.cgImage
        let context = createARGBBitmapContextFromImage(inImage: cgImage!)
        let height = cgImage!.height
        let width = cgImage!.width
        
        var rect: CGRect = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        context?.draw(cgImage!, in: rect)
        
        let pixelData = self.cgImage!.dataProvider!.data
        let data: UnsafePointer<UInt8> = CFDataGetBytePtr(pixelData)
        
        var minX = width
        var minY = height
        var maxX: Int = 0
        var maxY: Int = 0
        
        //Filter through data and look for non-transparent pixels.
        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = (width * y + x) * 4 /* 4 for A, R, G, B */
                
                if data[Int(pixelIndex)] != 0 { //Alpha value is not zero pixel is not transparent.
                    if (x < minX) {
                        minX = x
                    }
                    if (x > maxX) {
                        maxX = x
                    }
                    if (y < minY) {
                        minY = y
                    }
                    if (y > maxY) {
                        maxY = y
                    }
                }
            }
        }
        
        rect = CGRect( x: CGFloat(minX), y: CGFloat(minY), width: CGFloat(maxX-minX), height: CGFloat(maxY-minY))
        let imageScale:CGFloat = self.scale
        let cgiImage = self.cgImage?.cropping(to: rect)
        return UIImage(cgImage: cgiImage!, scale: imageScale, orientation: self.imageOrientation)
    }
    
    private func createARGBBitmapContextFromImage(inImage: CGImage) -> CGContext? {
        
        let width = cgImage!.width
        let height = cgImage!.height
        
        let bitmapBytesPerRow = width * 4
        let bitmapByteCount = bitmapBytesPerRow * height
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        if colorSpace == nil {
            return nil
        }
        
        let bitmapData = malloc(bitmapByteCount)
        if bitmapData == nil {
            return nil
        }
        
        let context = CGContext (data: bitmapData, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bitmapBytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
        
        return context
    }
}
