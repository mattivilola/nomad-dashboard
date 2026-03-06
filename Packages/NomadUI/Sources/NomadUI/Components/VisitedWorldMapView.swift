import AppKit
import MapKit
import NomadCore
import SwiftUI

public struct VisitedWorldMapView: NSViewRepresentable {
    private let places: [VisitedPlace]

    public init(places: [VisitedPlace]) {
        self.places = places
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.mapType = .mutedStandard
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsZoomControls = true
        mapView.showsTraffic = false
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: Coordinator.annotationReuseIdentifier)
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: Coordinator.clusterReuseIdentifier)
        return mapView
    }

    public func updateNSView(_ mapView: MKMapView, context: Context) {
        context.coordinator.apply(
            to: mapView,
            places: places,
            visitedCountryCodes: Set(places.compactMap { $0.countryCode?.uppercased() })
        )
    }

    public final class Coordinator: NSObject, MKMapViewDelegate {
        fileprivate static let annotationReuseIdentifier = "VisitedPlaceAnnotation"
        fileprivate static let clusterReuseIdentifier = "VisitedPlaceCluster"

        private var overlayCountryCodes: [ObjectIdentifier: String] = [:]
        private var visitedCountryCodes: Set<String> = []
        private var hasConfiguredInitialViewport = false

        fileprivate func apply(
            to mapView: MKMapView,
            places: [VisitedPlace],
            visitedCountryCodes: Set<String>
        ) {
            self.visitedCountryCodes = visitedCountryCodes

            mapView.removeAnnotations(mapView.annotations)
            mapView.removeOverlays(mapView.overlays)

            let overlays = CountryGeometryLoader.records
            overlayCountryCodes = overlays.reduce(into: [:]) { result, record in
                result[ObjectIdentifier(record.overlay as AnyObject)] = record.countryCode
            }
            mapView.addOverlays(overlays.map(\.overlay))

            let annotations = places.compactMap(VisitedPlaceAnnotation.init(place:))
            mapView.addAnnotations(annotations)

            if hasConfiguredInitialViewport == false {
                mapView.setVisibleMapRect(
                    MKMapRect.world,
                    edgePadding: NSEdgeInsets(top: 32, left: 32, bottom: 32, right: 32),
                    animated: false
                )
                hasConfiguredInitialViewport = true
            }
        }

        public func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            let isVisited = overlayCountryCodes[ObjectIdentifier(overlay as AnyObject)].map(visitedCountryCodes.contains) ?? false

            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                applyCountryStyling(to: renderer, isVisited: isVisited)
                return renderer
            }

            if let multiPolygon = overlay as? MKMultiPolygon {
                let renderer = MKMultiPolygonRenderer(multiPolygon: multiPolygon)
                applyCountryStyling(to: renderer, isVisited: isVisited)
                return renderer
            }

            return MKOverlayRenderer(overlay: overlay)
        }

        public func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil
            }

            if let cluster = annotation as? MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: Self.clusterReuseIdentifier,
                    for: cluster
                ) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: cluster, reuseIdentifier: Self.clusterReuseIdentifier)
                view.annotation = cluster
                view.canShowCallout = true
                view.markerTintColor = NSColor(hex: 0x0E8C92)
                view.glyphText = "\(cluster.memberAnnotations.count)"
                view.displayPriority = .required
                return view
            }

            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: Self.annotationReuseIdentifier,
                for: annotation
            ) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: Self.annotationReuseIdentifier)
            view.annotation = annotation
            view.canShowCallout = true
            view.animatesWhenAdded = false
            view.markerTintColor = NSColor(hex: 0xC85C34)
            view.glyphImage = NSImage(systemSymbolName: "mappin.circle.fill", accessibilityDescription: "Visited place")
            view.displayPriority = .required
            view.clusteringIdentifier = "visited-place"
            return view
        }

        private func applyCountryStyling(to renderer: MKOverlayPathRenderer, isVisited: Bool) {
            renderer.lineWidth = isVisited ? 1.2 : 0.7
            renderer.strokeColor = isVisited ? NSColor(hex: 0x0E8C92, alpha: 0.62) : NSColor(hex: 0x17303A, alpha: 0.14)
            renderer.fillColor = isVisited ? NSColor(hex: 0x0E8C92, alpha: 0.24) : NSColor(hex: 0x17303A, alpha: 0.03)
        }
    }
}

private final class VisitedPlaceAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?

    init?(place: VisitedPlace) {
        guard let coordinate = place.coordinate, CLLocationCoordinate2DIsValid(coordinate) else {
            return nil
        }

        self.coordinate = coordinate

        if let city = place.city, city.isEmpty == false {
            self.title = city
        } else {
            self.title = place.country
        }

        self.subtitle = place.city == nil ? (place.countryCode ?? place.country) : place.country
    }
}

private struct CountryOverlayRecord {
    let countryCode: String
    let overlay: any MKOverlay
}

private enum CountryGeometryLoader {
    static let records = load()

    private static func load() -> [CountryOverlayRecord] {
        guard
            let url = Bundle.module.url(forResource: "world-country-shapes", withExtension: "geojson"),
            let data = try? Data(contentsOf: url),
            let decoded = try? MKGeoJSONDecoder().decode(data)
        else {
            return []
        }

        let features = decoded.compactMap { $0 as? MKGeoJSONFeature }

        return features.flatMap { feature -> [CountryOverlayRecord] in
            guard let countryCode = countryCode(for: feature) else {
                return []
            }

            return feature.geometry.compactMap { geometry -> CountryOverlayRecord? in
                if let polygon = geometry as? MKPolygon {
                    return CountryOverlayRecord(countryCode: countryCode, overlay: polygon)
                }

                if let multiPolygon = geometry as? MKMultiPolygon {
                    return CountryOverlayRecord(countryCode: countryCode, overlay: multiPolygon)
                }

                return nil
            }
        }
    }

    private static func countryCode(for feature: MKGeoJSONFeature) -> String? {
        guard
            let properties = feature.properties,
            let jsonObject = try? JSONSerialization.jsonObject(with: properties),
            let dictionary = jsonObject as? [String: Any]
        else {
            return nil
        }

        let candidates = [
            dictionary["ISO_A2"],
            dictionary["ISO_A2_EH"],
            dictionary["WB_A2"],
            dictionary["POSTAL"]
        ]

        for candidate in candidates {
            if let value = candidate as? String, value.count == 2, value != "-99" {
                return value.uppercased()
            }
        }

        return nil
    }
}

private extension NSColor {
    convenience init(hex: UInt64, alpha: Double = 1) {
        self.init(
            srgbRed: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
