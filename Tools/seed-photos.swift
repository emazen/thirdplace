#!/usr/bin/env swift
// Generates a year of fake geotagged photos for testing the scan in the simulator.
// A London persona: home, work, a café, a climbing gym, a lido, a park, a bookshop, a pub,
// plus a festival and a few trips. Images are flat colour squares; only EXIF time + GPS matter.
//
// Usage: swift Tools/seed-photos.swift <output-folder>

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/SeedPhotos")
try? FileManager.default.removeItem(at: output)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

struct Spot {
    let lat: Double
    let lon: Double
    let rgb: (CGFloat, CGFloat, CGFloat)
}

let home = Spot(lat: 51.5560, lon: -0.0560, rgb: (0.80, 0.78, 0.74))
let work = Spot(lat: 51.5246, lon: -0.0786, rgb: (0.70, 0.74, 0.78))
let cafe = Spot(lat: 51.5450, lon: -0.0553, rgb: (0.78, 0.66, 0.55))
let climbing = Spot(lat: 51.5270, lon: -0.0550, rgb: (0.62, 0.66, 0.60))
let lido = Spot(lat: 51.5420, lon: -0.0610, rgb: (0.55, 0.72, 0.80))
let park = Spot(lat: 51.5362, lon: -0.0402, rgb: (0.55, 0.70, 0.52))
let bookshop = Spot(lat: 51.5620, lon: -0.0750, rgb: (0.74, 0.62, 0.66))
let pub = Spot(lat: 51.5297, lon: -0.0712, rgb: (0.60, 0.50, 0.42))
let glastonbury = Spot(lat: 51.1550, lon: -2.5850, rgb: (0.66, 0.74, 0.50))
let barcelona = Spot(lat: 41.4110, lon: 2.2210, rgb: (0.86, 0.70, 0.50))
let lisbon = Spot(lat: 38.7075, lon: -9.1365, rgb: (0.84, 0.76, 0.62))
let istanbul = Spot(lat: 41.0200, lon: 28.9730, rgb: (0.80, 0.60, 0.50))

// Deterministic randomness so the fixture is the same every run.
var state: UInt64 = 0x5EED
func random() -> Double {
    state = state &* 6364136223846793005 &+ 1442695040888963407
    return Double(state >> 11) / Double(1 << 53)
}
func chance(_ p: Double) -> Bool { random() < p }

let calendar = Calendar.current
let exifFormat: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = calendar.timeZone
    f.dateFormat = "yyyy:MM:dd HH:mm:ss"
    return f
}()

var count = 0
func photo(_ spot: Spot, _ date: Date) {
    let lat = spot.lat + (random() - 0.5) * 0.0005
    let lon = spot.lon + (random() - 0.5) * 0.0008
    let size = 96
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let shade = CGFloat(random() * 0.12 - 0.06)
    context.setFillColor(red: spot.rgb.0 + shade, green: spot.rgb.1 + shade, blue: spot.rgb.2 + shade, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    let image = context.makeImage()!

    let stamp = exifFormat.string(from: date)
    let seconds = calendar.timeZone.secondsFromGMT(for: date)
    let offset = String(format: "%@%02d:%02d", seconds >= 0 ? "+" : "-", abs(seconds) / 3600, abs(seconds) % 3600 / 60)
    let properties: [CFString: Any] = [
        kCGImagePropertyExifDictionary: [
            kCGImagePropertyExifDateTimeOriginal: stamp,
            kCGImagePropertyExifDateTimeDigitized: stamp,
            kCGImagePropertyExifOffsetTimeOriginal: offset,
            kCGImagePropertyExifOffsetTimeDigitized: offset
        ],
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFDateTime: stamp],
        kCGImagePropertyGPSDictionary: [
            kCGImagePropertyGPSLatitude: abs(lat),
            kCGImagePropertyGPSLatitudeRef: lat >= 0 ? "N" : "S",
            kCGImagePropertyGPSLongitude: abs(lon),
            kCGImagePropertyGPSLongitudeRef: lon >= 0 ? "E" : "W"
        ]
    ]
    count += 1
    let url = output.appendingPathComponent(String(format: "IMG_%04d.jpg", count))
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    CGImageDestinationFinalize(destination)
}

func at(_ day: Date, _ hour: Int, _ minute: Int? = nil) -> Date {
    calendar.date(bySettingHour: hour, minute: minute ?? Int(random() * 59), second: 0, of: day)!
}

func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
    calendar.date(from: DateComponents(year: y, month: m, day: d))!
}

// The last 52 weeks, Monday to Sunday.
let today = calendar.startOfDay(for: Date())
let thisMonday = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
let firstMonday = calendar.date(byAdding: .weekOfYear, value: -52, to: thisMonday)!

for week in 0..<52 {
    let monday = calendar.date(byAdding: .weekOfYear, value: week, to: firstMonday)!
    func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: monday)! }
    let month = calendar.component(.month, from: monday)
    let summer = (6...8).contains(month)

    for d in [1, 4] where chance(0.9) { photo(home, at(day(d), 22)) }
    for d in 0..<5 where chance(0.4) { photo(work, at(day(d), 13)) }
    for d in [1, 3] where chance(0.75) { photo(cafe, at(day(d), 8)) }
    for d in [1, 3] where chance(0.5) { photo(climbing, at(day(d), 19)) }
    if summer { for d in [5, 6] where chance(0.7) { photo(lido, at(day(d), 11)) } }
    if chance(0.6) { photo(park, at(day(6), 10)) }
    if chance(0.3) { photo(bookshop, at(day(5), 15)) }
    if chance(0.25) { photo(pub, at(day(4), 21)) }
}

// Moments, all inside the last year.
let thisYear = calendar.component(.year, from: today)
func pastDate(_ m: Int, _ d: Int) -> Date {
    let candidate = date(thisYear, m, d)
    return candidate <= today ? candidate : date(thisYear - 1, m, d)
}
for d in 0..<3 { for i in 0..<12 { photo(glastonbury, at(calendar.date(byAdding: .day, value: d, to: pastDate(6, 26))!, 13 + i % 10)) } }
for d in 0..<2 { for i in 0..<8 { photo(barcelona, at(calendar.date(byAdding: .day, value: d, to: pastDate(5, 30))!, 17 + i % 6)) } }
for i in 0..<12 { photo(lisbon, at(pastDate(12, 31), 21 + i % 3)) }
for i in 0..<10 { photo(istanbul, at(pastDate(8, 14), 17 + i % 4)) }

print("Wrote \(count) photos to \(output.path)")
