//alert_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class Alert {
  final String alertId;
  final String alertType;
  final String safetyCode;
  final bool isActive;
  final Timestamp alertStart;
  final Timestamp alertEnd;
  final Report report;
  final GeoPoint userLocationStart;
  final GeoPoint userLocationEnd;

  Alert({
    required this.alertId,
    required this.alertType,
    required this.safetyCode,
    required this.isActive,
    required this.alertStart,
    required this.alertEnd,
    required this.report,
    required this.userLocationStart,
    required this.userLocationEnd,
  });

  // Factory constructor to create an empty alert
  factory Alert.empty() {
    return Alert(
      alertId: '',
      alertType: '',
      safetyCode: '',
      isActive: false,
      alertStart: Timestamp.now(),
      alertEnd: Timestamp.now(),
      report: Report.empty(),
      userLocationStart: const GeoPoint(0, 0),
      userLocationEnd: const GeoPoint(0, 0),
    );
  }

  factory Alert.fromFirestore(Map<String, dynamic> data, String id) {
    return Alert(
      alertId: id,
      alertType: data['type'] ?? '',
      safetyCode: data['safety_code'] ?? '',
      isActive : data['isActive'] ?? false,
      alertStart: data['alert_duration']['alert_start'] ?? Timestamp.now(),
      alertEnd: data['alert_duration']['alert_end'] ?? Timestamp.now(),
      report: Report.fromFirestore(data['report'] ?? {}),
      userLocationStart: data['user_locations']['user_location_start'] as GeoPoint,
      userLocationEnd: data['user_locations']['user_location_end'] as GeoPoint,
    );
  }
}

class Report {
  final String reportDescription;
  final String reportType;
  final GeoPoint? reportGeopoint;

  Report({
    required this.reportDescription,
    required this.reportType,
    this.reportGeopoint,
  });

  factory Report.fromFirestore(Map<String, dynamic> data)
  {
    return Report(
      reportDescription: data['report_description'] ?? '',
      reportType: data['report_type'] ?? '',
      reportGeopoint: data['report_geopoint'] as GeoPoint?,
    );
  }

  factory Report.empty()
  {
    return Report(
      reportDescription: '',
      reportType: '',
      reportGeopoint: const GeoPoint (0,0),
    );
  }

}
