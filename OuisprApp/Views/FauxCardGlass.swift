// OuisprApp/Views/FauxCardGlass.swift
// The pre-rendered glass of the drifting dictation cards: one image, drawn once, stretched.
import SwiftUI
import UIKit
import OuisprCore

/// The drifting cards' glass, drawn once per appearance and display scale into one small
/// image that every card stretches to its width.
///
/// WHY an image (Alex, 26 Nov 2026: « faux verre par défaut pour les tuiles qui dérivent »):
/// live glass samples and blurs what is behind each card on every frame the card moves,
/// and a drifting row moves every frame. A shape drawn by SwiftUI (the first stand-in)
/// is rasterised by the app itself. A stretchable image is decoded once and handed to the
/// render server as a layer's contents: moving it is a translation, nothing is sampled,
/// blurred or redrawn, and every card on screen shares the same bitmap.
///
/// What it keeps of Liquid Glass: a translucent body tinted with the mist's blue (the
/// mist moves behind it, it is not blurred), a reflection across the top third, a light
/// rim brighter at the top, and the soft shadow under the card.
enum FauxCardGlass {
    /// The card's corner radius, the size the image keeps unstretched at each end.
    static let corner: CGFloat = DictationCloudCard.cornerRadius
    /// Room around the card for the shadow, outside the card's frame.
    static let shadowPad: CGFloat = 20

    @MainActor private static var cache: [Key: UIImage] = [:]

    private struct Key: Hashable {
        let dark: Bool
        let scale: CGFloat
    }

    /// The image for this appearance, made on first use.
    @MainActor
    static func image(dark: Bool, scale: CGFloat) -> UIImage {
        let key = Key(dark: dark, scale: scale)
        if let image = cache[key] { return image }
        let image = render(dark: dark, scale: scale)
        cache[key] = image
        return image
    }

    /// The cap insets that keep the corners and the shadow unstretched: only a 2 pt
    /// column in the middle is stretched, and the image's look runs top to bottom, so a
    /// stretched card is the same glass at any width.
    static var capInsets: EdgeInsets {
        let inset = corner + shadowPad
        return EdgeInsets(top: inset, leading: inset, bottom: inset, trailing: inset)
    }

    private static func render(dark: Bool, scale: CGFloat) -> UIImage {
        let height = DictationCloudCard.height
        let cardSize = CGSize(width: 2 * corner + 2, height: height)
        let size = CGSize(width: cardSize.width + 2 * shadowPad, height: cardSize.height + 2 * shadowPad)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let card = CGRect(origin: CGPoint(x: shadowPad, y: shadowPad), size: cardSize)
            let path = UIBezierPath(roundedRect: card, cornerRadius: corner).cgPath
            let space = CGColorSpaceCreateDeviceRGB()

            // The shadow, cast by a filled card; the fill is cleared below, so the shadow
            // shows only outside the card and never darkens the glass.
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: 4), blur: 18,
                         color: UIColor(red: 0.1, green: 0.16, blue: 0.3, alpha: dark ? 0.32 : 0.11).cgColor)
            cg.addPath(path)
            cg.setFillColor(UIColor.white.withAlphaComponent(dark ? 0.02 : 0.25).cgColor)
            cg.fillPath()
            cg.restoreGState()

            // The body: in light, whiter at the top and the mist's blue at the bottom; in dark,
            // a shade darker than the screen, as dark Liquid Glass is.
            cg.saveGState()
            cg.addPath(path)
            cg.clip()
            cg.clear(card)
            let mist = UIColor(red: 0xDB / 255, green: 0xEA / 255, blue: 0xFE / 255, alpha: 1)
            let sky = UIColor(red: 0x93 / 255, green: 0xC5 / 255, blue: 0xFD / 255, alpha: 1)
            let body: [CGColor] = dark
                ? [UIColor.black.withAlphaComponent(0.2).cgColor, UIColor.black.withAlphaComponent(0.26).cgColor]
                : [UIColor.white.withAlphaComponent(0.8).cgColor, mist.withAlphaComponent(0.62).cgColor]
            if let gradient = CGGradient(colorsSpace: space, colors: body as CFArray, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: card.minY),
                                      end: CGPoint(x: 0, y: card.maxY), options: [])
            }
            // The reflection: a band of light across the top third, fading downwards.
            let shine: [CGColor] = [
                UIColor.white.withAlphaComponent(dark ? 0.04 : 0.55).cgColor,
                UIColor.white.withAlphaComponent(0).cgColor
            ]
            if let gradient = CGGradient(colorsSpace: space, colors: shine as CFArray, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: card.minY),
                                      end: CGPoint(x: 0, y: card.minY + card.height * 0.38), options: [])
            }
            // A faint glow along the bottom edge, where glass gathers light.
            let glow: [CGColor] = [
                UIColor.white.withAlphaComponent(0).cgColor,
                UIColor.white.withAlphaComponent(dark ? 0.02 : 0.22).cgColor
            ]
            if let gradient = CGGradient(colorsSpace: space, colors: glow as CFArray, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: card.maxY - 14),
                                      end: CGPoint(x: 0, y: card.maxY), options: [])
            }
            cg.restoreGState()

            // The rim: a hairline, bright at the top, faint at the bottom.
            let rimWidth: CGFloat = 1
            let rimRect = card.insetBy(dx: rimWidth / 2, dy: rimWidth / 2)
            let rim = UIBezierPath(roundedRect: rimRect, cornerRadius: corner - rimWidth / 2).cgPath
            cg.saveGState()
            cg.addPath(rim)
            cg.setLineWidth(rimWidth)
            cg.replacePathWithStrokedPath()
            cg.clip()
            let edge: [CGColor] = dark
                ? [sky.withAlphaComponent(0.3).cgColor, sky.withAlphaComponent(0.08).cgColor, sky.withAlphaComponent(0.16).cgColor]
                : [UIColor.white.withAlphaComponent(0.9).cgColor, UIColor.white.withAlphaComponent(0.3).cgColor,
                   UIColor.white.withAlphaComponent(0.6).cgColor]
            if let gradient = CGGradient(colorsSpace: space, colors: edge as CFArray, locations: [0, 0.6, 1]) {
                cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: card.minY),
                                      end: CGPoint(x: 0, y: card.maxY), options: [])
            }
            cg.restoreGState()
        }
    }
}

/// A card's pre-rendered glass, behind its content, shadow included.
struct FauxCardGlassBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Image(uiImage: FauxCardGlass.image(dark: colorScheme == .dark, scale: displayScale))
            .resizable(capInsets: FauxCardGlass.capInsets, resizingMode: .stretch)
            .padding(-FauxCardGlass.shadowPad)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
