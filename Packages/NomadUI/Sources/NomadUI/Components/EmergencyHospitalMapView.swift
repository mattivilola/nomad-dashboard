import AppKit
import CoreLocation
import MapKit
import SwiftUI

public struct EmergencyHospitalMapView: NSViewRepresentable {
    private let hospitalName: String
    private let coordinate: CLLocationCoordinate2D

    public init(hospitalName: String, coordinate: CLLocationCoordinate2D) {
        self.hospitalName = hospitalName
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
        context.coordinator.apply(to: mapView, hospitalName: hospitalName, coordinate: coordinate)
    }

    public final class Coordinator: NSObject, MKMapViewDelegate {
        fileprivate static let annotationReuseIdentifier = "EmergencyHospitalAnnotation"
        private var currentAnnotationIdentifier: String?

        fileprivate func apply(to mapView: MKMapView, hospitalName: String, coordinate: CLLocationCoordinate2D) {
            let identifier = "\(hospitalName)|\(coordinate.latitude)|\(coordinate.longitude)"
            guard currentAnnotationIdentifier != identifier else {
                return
            }

            currentAnnotationIdentifier = identifier
            mapView.removeAnnotations(mapView.annotations)

            let annotation = EmergencyHospitalAnnotation(hospitalName: hospitalName, coordinate: coordinate)
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
            view.markerTintColor = NSColor(
                srgbRed: 0xC4 as CGFloat / 255,
                green: 0x54 as CGFloat / 255,
                blue: 0x54 as CGFloat / 255,
                alpha: 1
            )
            view.glyphImage = NSImage(systemSymbolName: "cross.case.fill", accessibilityDescription: "Hospital")
            view.displayPriority = .required
            return view
        }
    }
}

private final class EmergencyHospitalAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?

    init(hospitalName: String, coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        title = hospitalName
    }
}
