//
//  Document.swift
//  HyperCardPreview
//
//  Created by Pierre Lorenzi on 06/03/2017.
//  Copyright © 2017 Pierre Lorenzi. All rights reserved.
//

import Cocoa
import HyperCardCommon
import QuickLook

struct RgbColor {
    var r: UInt8
    var g: UInt8
    var b: UInt8
    var a: UInt8
    
    init(a: UInt8, r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
}

struct RgbColor2 {
    var color0: RgbColor
    var color1: RgbColor
}

let RgbWhite = RgbColor(a: 255, r: 255, g: 255, b: 255)
let RgbBlack = RgbColor(a: 255, r: 0, g: 0, b: 0)

let RgbWhite2 = RgbColor2(color0: RgbWhite, color1: RgbWhite)
let RgbBlack2 = RgbColor2(color0: RgbBlack, color1: RgbBlack)

let RgbColorSpace = CGColorSpaceCreateDeviceRGB()
let BitmapInfo:CGBitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
let BitsPerComponent = 8
let BitsPerPixel = 32




class Document: NSDocument {
    
    var file: HyperCardFile!
    var browser: Browser!
    
    var pixels: [RgbColor2] = []
    
    var panels: [InfoPanelController] = []
    
    @IBOutlet weak var view: DocumentView!
    
    override var windowNibName: String? {
        return "Document"
    }
    
    override func read(from url: URL, ofType typeName: String) throws {
        file = HyperCardFile(path: url.path)
        
    }
    
    override func windowControllerDidLoadNib(_ windowController: NSWindowController) {
        super.windowControllerDidLoadNib(windowController)
        
        let window = self.windowControllers[0].window!
        let currentFrame = window.frame
        let newFrame = window.frameRect(forContentRect: NSMakeRect(currentFrame.origin.x, currentFrame.origin.y, CGFloat(file.stack.size.width), CGFloat(file.stack.size.height)))
        window.setFrame(newFrame, display: false)
        view.frame = NSMakeRect(0, 0, CGFloat(file.stack.size.width), CGFloat(file.stack.size.height))
        
        browser = Browser(stack: file.stack)
        browser.cardIndex = 0
        
        let width = file.stack.size.width;
        let height = file.stack.size.height;
        self.pixels = [RgbColor2](repeating: RgbWhite2, count: width*height*2)
        refresh()
    }
    
    func refresh() {
        
        let image = self.browser.image
        for x in 0..<image.width {
            for y in 0..<image.height {
                let value = image[x, y] ? RgbBlack2 : RgbWhite2
                let offset0 = x + 2*y*image.width
                let offset1 = offset0 + image.width
                self.pixels[offset0] = value
                self.pixels[offset1] = value
            }
        }
        let data = NSMutableData(bytes: &pixels, length: self.pixels.count * 2 * MemoryLayout<RgbColor>.size)
        let providerRef = CGDataProvider(data: data)
        let width = file.stack.size.width;
        let height = file.stack.size.height;
        let cgimage = CGImage(
            width: width*2,
            height: height*2,
            bitsPerComponent: BitsPerComponent,
            bitsPerPixel: BitsPerPixel,
            bytesPerRow: width*2 * MemoryLayout<RgbColor>.size,
            space: RgbColorSpace,
            bitmapInfo: BitmapInfo,
            provider: providerRef!,
            decode: nil,
            shouldInterpolate: true,
            intent: CGColorRenderingIntent.defaultIntent)
        CATransaction.setDisableActions(true)
        view.layer!.contents = cgimage
    }
    
    func goToFirstPage(_ sender: AnyObject) {
        browser.cardIndex = 0
        refresh()
    }
    
    func goToLastPage(_ sender: AnyObject) {
        browser.cardIndex = browser.stack.cards.count-1
        refresh()
    }
    
    func goToNextPage(_ sender: AnyObject) {
        var cardIndex = browser.cardIndex
        cardIndex += 1
        if cardIndex == browser.stack.cards.count {
            cardIndex = 0
        }
        browser.cardIndex = cardIndex
        refresh()
    }
    
    func goToPreviousPage(_ sender: AnyObject) {
        var cardIndex = browser.cardIndex
        cardIndex -= 1
        if cardIndex == -1 {
            cardIndex = browser.stack.cards.count - 1
        }
        browser.cardIndex = cardIndex
        refresh()
    }
    
    func displayOnlyBackground(_ sender: AnyObject) {
        browser.displayOnlyBackground = !browser.displayOnlyBackground
        refresh()
    }
    
    func displayButtonScriptBorders(_ sender: AnyObject) {
        createScriptBorders(includingFields: false)
    }
    
    func displayPartScriptBorders(_ sender: AnyObject) {
        createScriptBorders(includingFields: true)
    }
    
    func hideScriptBorders(_ sender: AnyObject) {
        removeScriptBorders()
    }
    
    func createScriptBorders(includingFields: Bool) {
        
        removeScriptBorders()
        createScriptBorders(in: browser.currentBackground, includingFields: includingFields, cardContents: browser.currentCard.backgroundPartContents)
        if !browser.displayOnlyBackground {
            createScriptBorders(in: browser.currentCard, includingFields: includingFields, cardContents: nil)
        }
        
    }
    
    func createScriptBorders(in layer: Layer, includingFields: Bool, cardContents: [Card.BackgroundPartContent]?) {
        
        for part in layer.parts {
            
            /* Exclude fields if necessary */
            if case LayerPart.field(_) = part, !includingFields {
                continue
            }
            
            /* Convert the rectangle into current coordinates */
            let rectangle = part.part.rectangle
            let frame = NSMakeRect(CGFloat(rectangle.x), CGFloat(file.stack.size.height - rectangle.bottom), CGFloat(rectangle.width), CGFloat(rectangle.height))
            
            /* Create a view */
            let view = ScriptBorderView(frame: frame, part: part, content: retrieveContent(part: part, cardContents: cardContents), document: self)
            view.wantsLayer = true
            view.layer!.borderColor = NSColor.blue.cgColor
            view.layer!.borderWidth = 1
            view.layer!.backgroundColor = CGColor(red: 0, green: 0, blue: 1, alpha: 0.03)
            
            self.windowControllers[0].window!.contentView!.addSubview(view)
            
        }
        
    }
    
    func retrieveContent(part: LayerPart, cardContents: [Card.BackgroundPartContent]?) -> HString {
        
        if let contents = cardContents {
            if let content = contents.first(where: {$0.partIdentifier == part.part.identifier}) {
                return content.partContent.string
            }
            return ""
        }
        
        switch part {
        case .field(let field):
            return field.content.string
        case .button(let button):
            return button.content
        }
    }
    
    func removeScriptBorders() {
        
        for view in self.windowControllers[0].window!.contentView!.subviews {
            guard view !== self.view else {
                continue
            }
            view.removeFromSuperview()
        }
    }
    
    func displayStackInfo(_ sender: AnyObject) {
        displayInfo().displayStack(browser.stack)
    }
    
    func displayBackgroundInfo(_ sender: AnyObject) {
        displayInfo().displayBackground(browser.currentBackground)
    }
    
    func displayCardInfo(_ sender: AnyObject) {
        displayInfo().displayCard(browser.currentCard)
    }
    
    func displayInfo() -> InfoPanelController {
        removeScriptBorders()
        
        let controller = InfoPanelController()
        Bundle.main.loadNibNamed("InfoPanel", owner: controller, topLevelObjects: nil)
        controller.setup()
        controller.window.makeKeyAndOrderFront(nil)
        panels.append(controller)
        return controller
    }
    
}


