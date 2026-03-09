import AppKit
import CoreLocation
import MapKit
import SwiftUI

public struct FuelStationMapView: NSViewRepresentable {
    private let stationName: String
    private let coordinate: CLLocationCoordinate2D

    public init(stationName: String, coordinate: CLLocationCoordinate2D) {
        self.stationName = stationName
        self.coordinate = coordinate
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
        mapView.showsZoomControls = true
        mapView.showsTraffic = false
        mapView.pointOfInterestFilter = .excludingAll
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: Coordinator.annotationReuseIdentifier)
        return mapView
    }

    public func updateNSView(_ mapView: MKMapView, context: Context) {
        context.coordinator.apply(to: mapView, stationName: stationName, coordinate: coordinate)
    }

    public final class Coordinator: NSObject, MKMapViewDelegate {
        fileprivate static let annotationReuseIdentifier = "FuelStationAnnotation"
        private var currentAnnotationIdentifier: String?

        fileprivate func apply(to mapView: MKMapView, stationName: String, coordinate: CLLocationCoordinate2D) {
            let identifier = "\(stationName)|\(coordinate.latitude)|\(coordinate.longitude)"
            guard currentAnnotationIdentifier != identifier else {
                return
            }

            currentAnnotationIdentifier = identifier
            mapView.removeAnnotations(mapView.annotations)

            let annotation = FuelStationAnnotation(stationName: stationName, coordinate: coordinate)
            mapView.addAnnotation(annotation)

            let region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 2_200,
                longitudinalMeters: 2_200
            )
            mapView.setRegion(region, animated: false)
        }

        public func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil
            }

            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: Self.annotationReuseIdentifier,
                for: annotation
            ) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: Self.annotationReuseIdentifier)
            view.annotation = annotation
            view.canShowCallout = true
            view.animatesWhenAdded = false
            view.markerTintColor = NSColor(hex: 0x0E8C92)
            view.glyphImage = NSImage(systemSymbolName: "fuelpump.fill", accessibilityDescription: "Fuel station")
            view.displayPriority = .required
            return view
        }
    }
}

private final class FuelStationAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?

    init(stationName: String, coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        title = stationName
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
