import Foundation

// Regenerates Packages/NomadCore/Sources/NomadCore/Resources/country-bounds.json: one bounding box per
// country (minLatitude, maxLatitude, minLongitude, maxLongitude), used to frame a planned trip on a map.
// Run it through scripts/update-country-bounds.sh when the country shapes change; the app never computes this.
//
// Input: the Natural Earth 1:110m admin-0 countries (public domain) that the visited-places map ships
// (Packages/NomadUI/Sources/NomadUI/Resources/world-country-shapes.geojson).
//
// How a country's box is chosen (the shapes are polygons per landmass):
//  - Start with the largest polygon (main landmass).
//  - Repeatedly add every polygon whose gap to the box grown so far is at most `joinGapDegrees` in both
//    latitude and longitude. Neighbouring islands (Indonesia, Japan, Fiji) join; far-flung territories
//    (French Guiana for France, Alaska and Hawaii for the US, Greenland for Denmark, the Canary Islands for
//    Spain) stay out.
//  - Longitudes are handled on the circle, so a country split at the antimeridian (Fiji, Russia) is one
//    box that crosses it: its maximum longitude is then above 180 (subtract 360 for the real longitude).
//  - Boxes are rounded outwards to 0.01 degrees.
//
// Countries that the 1:110m data leaves out (mostly small states and islands) get the approximate extents
// in `supplement` below, entered by hand and rounded outwards to 0.1 degrees.
//
// Usage: update-country-bounds.swift [--geojson FILE] [--output FILE]

let joinGapDegrees = 4.0

/// minLatitude, maxLatitude, minLongitude, maxLongitude for countries missing from the 1:110m data.
let supplement: [String: [Double]] = [
    "AD": [42.4, 42.7, 1.4, 1.8],
    "AW": [12.4, 12.7, -70.1, -69.8],
    "BB": [13.0, 13.4, -59.7, -59.4],
    "BH": [25.8, 26.3, 50.3, 50.9],
    "BM": [32.2, 32.4, -64.9, -64.6],
    "CV": [14.8, 17.3, -25.4, -22.6],
    "CW": [12.0, 12.4, -69.2, -68.7],
    "HK": [22.1, 22.6, 113.8, 114.5],
    "KY": [19.2, 19.8, -81.5, -79.7],
    "LC": [13.7, 14.1, -61.1, -60.8],
    "LI": [47.0, 47.3, 9.4, 9.7],
    "MC": [43.7, 43.8, 7.4, 7.5],
    "MO": [22.1, 22.3, 113.5, 113.7],
    "MT": [35.8, 36.1, 14.1, 14.6],
    "MU": [-20.6, -19.9, 57.3, 57.9],
    "MV": [-0.7, 7.1, 72.6, 73.8],
    "SC": [-4.9, -4.5, 55.2, 55.9],
    "SG": [1.1, 1.5, 103.6, 104.1],
    "SM": [43.9, 44.0, 12.4, 12.6]
]

struct Box {
    var minLat: Double
    var maxLat: Double
    /// Longitudes may exceed 180 after unwrapping.
    var minLon: Double
    var maxLon: Double

    /// Gap between two intervals; 0 when they overlap or touch.
    static func gap(_ lowA: Double, _ highA: Double, _ lowB: Double, _ highB: Double) -> Double {
        max(lowA - highB, lowB - highA, 0)
    }

    mutating func formUnion(_ other: Box) {
        minLat = min(minLat, other.minLat)
        maxLat = max(maxLat, other.maxLat)
        minLon = min(minLon, other.minLon)
        maxLon = max(maxLon, other.maxLon)
    }
}

struct Part {
    var box: Box
    let area: Double
}

/// Area in square degrees of longitude and latitude, with longitude scaled by the cosine of the mean latitude.
func ringArea(_ ring: [[Double]]) -> Double {
    let meanLatitude = ring.map { $0[1] }.reduce(0, +) / Double(ring.count)
    let scale = cos(meanLatitude * .pi / 180)
    let origin = ring[0]
    var sum = 0.0
    for index in ring.indices {
        let a = ring[index]
        let b = ring[(index + 1) % ring.count]
        sum += ((a[0] - origin[0]) * scale) * (b[1] - origin[1]) - ((b[0] - origin[0]) * scale) * (a[1] - origin[1])
    }
    return abs(sum) / 2
}

func part(of polygon: [[[Double]]]) -> Part? {
    guard let outer = polygon.first, outer.count > 2 else { return nil }
    let lons = outer.map { $0[0] }
    let lats = outer.map { $0[1] }
    return Part(
        box: Box(minLat: lats.min()!, maxLat: lats.max()!, minLon: lons.min()!, maxLon: lons.max()!),
        area: ringArea(outer)
    )
}

/// Smallest longitude arc that holds all parts, as (low, high) with high possibly above 180.
func wrapped(_ boxes: [Box]) -> (Double, Double) {
    // Sort the intervals on the circle and find the largest gap; the arc is everything else.
    let intervals = boxes.map { ($0.minLon, $0.maxLon) }.sorted { $0.0 < $1.0 }
    var merged: [(Double, Double)] = []
    for interval in intervals {
        if let last = merged.last, interval.0 <= last.1 {
            merged[merged.count - 1].1 = max(last.1, interval.1)
        } else {
            merged.append(interval)
        }
    }
    var bestGap = (merged.first!.0 + 360) - merged.last!.1
    var start = merged.first!.0
    var end = merged.last!.1
    for index in 1..<max(merged.count, 1) where index < merged.count {
        let gap = merged[index].0 - merged[index - 1].1
        if gap > bestGap {
            bestGap = gap
            start = merged[index].0
            end = merged[index - 1].1 + 360
        }
    }
    return (start, end)
}

func countryCode(_ properties: [String: Any]) -> String? {
    for key in ["ISO_A2", "ISO_A2_EH"] {
        if let value = properties[key] as? String, value.count == 2, value != "-99" {
            return value.uppercased()
        }
    }
    return nil
}

func roundedDown(_ value: Double, _ places: Double) -> Double { (value * places).rounded(.down) / places }
func roundedUp(_ value: Double, _ places: Double) -> Double { (value * places).rounded(.up) / places }

// MARK: - Main

let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
var geojsonURL = repoRoot.appendingPathComponent("Packages/NomadUI/Sources/NomadUI/Resources/world-country-shapes.geojson")
var outputURL = repoRoot.appendingPathComponent("Packages/NomadCore/Sources/NomadCore/Resources/country-bounds.json")

var arguments = CommandLine.arguments.dropFirst()
while let argument = arguments.popFirst() {
    switch argument {
    case "--geojson": geojsonURL = URL(fileURLWithPath: arguments.popFirst() ?? "")
    case "--output": outputURL = URL(fileURLWithPath: arguments.popFirst() ?? "")
    default:
        FileHandle.standardError.write(Data("Unknown argument: \(argument)\n".utf8))
        exit(64)
    }
}

guard let data = try? Data(contentsOf: geojsonURL),
      let collection = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let features = collection["features"] as? [[String: Any]]
else {
    FileHandle.standardError.write(Data("Cannot read \(geojsonURL.path)\n".utf8))
    exit(66)
}

var partsByCountry: [String: [Part]] = [:]
for feature in features {
    guard let properties = feature["properties"] as? [String: Any], let code = countryCode(properties),
          let geometry = feature["geometry"] as? [String: Any], let type = geometry["type"] as? String
    else { continue }

    let polygons: [[[[Double]]]]
    switch type {
    case "Polygon": polygons = (geometry["coordinates"] as? [[[Double]]]).map { [$0] } ?? []
    default: polygons = geometry["coordinates"] as? [[[[Double]]]] ?? []
    }
    partsByCountry[code, default: []] += polygons.compactMap(part(of:))
}

var bounds: [String: [Double]] = [:]
for (code, parts) in partsByCountry where parts.isEmpty == false {
    var remaining = parts.sorted { $0.area > $1.area }
    var members = [remaining.removeFirst()]
    var union = members[0].box

    var grew = true
    while grew {
        grew = false
        for (index, candidate) in remaining.enumerated().reversed() {
            // Longitude gap on the circle: try the part as is and shifted by a whole turn.
            let lonGap = [-360.0, 0, 360].map { shift in
                Box.gap(union.minLon, union.maxLon, candidate.box.minLon + shift, candidate.box.maxLon + shift)
            }.min()!
            let latGap = Box.gap(union.minLat, union.maxLat, candidate.box.minLat, candidate.box.maxLat)
            if lonGap <= joinGapDegrees, latGap <= joinGapDegrees {
                var box = candidate.box
                // Shift the part so it continues the union across the antimeridian.
                for shift in [-360.0, 0, 360] where Box.gap(union.minLon, union.maxLon, box.minLon + shift, box.maxLon + shift) == lonGap {
                    box.minLon += shift
                    box.maxLon += shift
                    break
                }
                union.formUnion(box)
                members.append(Part(box: box, area: candidate.area))
                remaining.remove(at: index)
                grew = true
            }
        }
    }

    let (low, high) = wrapped(members.map(\.box))
    bounds[code] = [
        roundedDown(union.minLat, 100), roundedUp(union.maxLat, 100),
        roundedDown(low, 100), roundedUp(high, 100)
    ]
}
for (code, box) in supplement where bounds[code] == nil {
    bounds[code] = box
}

var lines: [String] = []
for code in bounds.keys.sorted() {
    let box = bounds[code]!.map { String(format: "%g", $0) }.joined(separator: ", ")
    lines.append("    \"\(code)\": [\(box)]")
}
let json = """
{
  "source": "Natural Earth 1:110m admin-0 countries (public domain), plus hand-entered extents for small states missing there",
  "format": "[minLatitude, maxLatitude, minLongitude, maxLongitude]; a maximum longitude above 180 means the box crosses the antimeridian",
  "bounds": {
\(lines.joined(separator: ",\n"))
  }
}

"""
try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try json.write(to: outputURL, atomically: true, encoding: .utf8)
print("Wrote \(outputURL.path) (\(bounds.count) countries)")
