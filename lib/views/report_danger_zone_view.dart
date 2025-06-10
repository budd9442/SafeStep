import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ReportDangerZoneView extends StatefulWidget {
  final bool internal;
  final LatLng? currentPosition;
  final double? initialRadius;
  final Function(LatLng, double)? onDangerZoneChanged;
  const ReportDangerZoneView({super.key, this.internal = false, this.currentPosition, this.initialRadius, this.onDangerZoneChanged});
  @override
  State<ReportDangerZoneView> createState() => _ReportDangerZoneViewState();
}

class _ReportDangerZoneViewState extends State<ReportDangerZoneView> {
  late TextEditingController _latController;
  late TextEditingController _lngController;
  late double _radius;
  String? _description;
  LatLng? _currentPosition;

  @override
  void initState() {
    super.initState();
    _radius = widget.initialRadius ?? 50.0;
    if (widget.currentPosition != null) {
      _currentPosition = widget.currentPosition;
      _latController = TextEditingController(text: _currentPosition!.latitude.toStringAsFixed(7));
      _lngController = TextEditingController(text: _currentPosition!.longitude.toStringAsFixed(7));
    } else {
      _latController = TextEditingController(text: '0.0');
      _lngController = TextEditingController(text: '0.0');
      _fetchCurrentLocation();
    }
  }

  Future<void> _fetchCurrentLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _currentPosition = LatLng(pos.latitude, pos.longitude);
        _latController.text = pos.latitude.toStringAsFixed(7);
        _lngController.text = pos.longitude.toStringAsFixed(7);
        _updateDangerZone();
      });
    } catch (e) {
      // Optionally show error
    }
  }

  void _updateDangerZone() {
    final lat = double.tryParse(_latController.text) ?? 0.0;
    final lng = double.tryParse(_lngController.text) ?? 0.0;
    if (widget.onDangerZoneChanged != null) {
      widget.onDangerZoneChanged!(LatLng(lat, lng), _radius);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.all(18.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Describe the danger zone:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Describe what makes this area unsafe...',
              border: OutlineInputBorder(),
            ),
            onChanged: (val) => _description = val,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _latController,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Latitude', border: OutlineInputBorder()),
                  onChanged: (_) => setState(_updateDangerZone),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _lngController,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Longitude', border: OutlineInputBorder()),
                  onChanged: (_) => setState(_updateDangerZone),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Text('Radius: '),
              Expanded(
                child: Slider(
                  value: _radius,
                  min: 10,
                  max: 200,
                  divisions: 38,
                  label: '${_radius.toStringAsFixed(0)} m',
                  onChanged: (val) => setState(() {
                    _radius = val;
                    _updateDangerZone();
                  }),
                ),
              ),
              SizedBox(width: 8),
              Text('${_radius.toStringAsFixed(0)} m'),
            ],
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            icon: const Icon(Icons.my_location),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8F5FE8)),
            onPressed: (_currentPosition == null ||
                (_latController.text == _currentPosition?.latitude.toStringAsFixed(7) &&
                 _lngController.text == _currentPosition?.longitude.toStringAsFixed(7)))
              ? null
              : () {
                  _latController.text = _currentPosition!.latitude.toStringAsFixed(7);
                  _lngController.text = _currentPosition!.longitude.toStringAsFixed(7);
                  setState(_updateDangerZone);
                },
            label: const Text('Set to Current Location'),
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: () async {
              final lat = double.tryParse(_latController.text) ?? 0.0;
              final lng = double.tryParse(_lngController.text) ?? 0.0;
              final desc = _description?.trim() ?? '';
              final radius = _radius;
              await FirebaseFirestore.instance.collection('dangerzones').add({
                'lat': lat,
                'lng': lng,
                'radius': radius,
                'description': desc,
                'reportedAt': FieldValue.serverTimestamp(),
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Danger zone reported. Thank you!')),
              );
              if (!widget.internal) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE0006A)),
            child: const Text('Report', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (widget.internal) return content;
    return Scaffold(appBar: AppBar(title: const Text('Report Danger Zone')), body: content);
  }
}
