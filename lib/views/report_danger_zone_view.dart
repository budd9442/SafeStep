import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class ReportDangerZoneView extends StatefulWidget {
  final LatLng? currentPosition;
  final double? initialRadius;
  final Function(LatLng, double)? onDangerZoneChanged;
  const ReportDangerZoneView({super.key, this.currentPosition, this.initialRadius, this.onDangerZoneChanged});
  @override
  State<ReportDangerZoneView> createState() => _ReportDangerZoneViewState();
}

class _ReportDangerZoneViewState extends State<ReportDangerZoneView> {
  late TextEditingController _descriptionController;
  late double _radius;
  LatLng? _selectedPosition;
  LatLng? _currentPosition;
  GoogleMapController? _mapController;
  bool _isLoading = true;
  bool _isSubmitting = false;
  Set<Circle> _circles = {};
  Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _radius = widget.initialRadius ?? 50.0;
    _descriptionController = TextEditingController();
    _selectedPosition = widget.currentPosition;
    _fetchCurrentLocation();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _fetchCurrentLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _currentPosition = LatLng(pos.latitude, pos.longitude);
        if (_selectedPosition == null) {
          _selectedPosition = _currentPosition;
        }
        _isLoading = false;
        _updateMapMarkers();
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to get current location: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _updateMapMarkers() {
    if (_selectedPosition != null) {
      setState(() {
        _markers = {
          Marker(
            markerId: const MarkerId('danger_zone_center'),
            position: _selectedPosition!,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: const InfoWindow(
              title: 'Danger Zone Center',
              snippet: 'Tap to move location',
            ),
          ),
        };

        _circles = {
          Circle(
            circleId: const CircleId('danger_zone_circle'),
            center: _selectedPosition!,
            radius: _radius,
            fillColor: Colors.red.withOpacity(0.2),
            strokeColor: Colors.red,
            strokeWidth: 2,
          ),
        };
      });
    }
  }

  void _onMapTap(LatLng position) {
    setState(() {
      _selectedPosition = position;
      _updateMapMarkers();
      _updateDangerZone();
    });
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    if (_selectedPosition != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(_selectedPosition!, 16.0),
      );
    }
  }

  void _updateDangerZone() {
    if (_selectedPosition != null && widget.onDangerZoneChanged != null) {
      widget.onDangerZoneChanged!(_selectedPosition!, _radius);
    }
  }

  Future<void> _submitDangerZone() async {
    if (_selectedPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a location on the map'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final desc = _descriptionController.text.trim();
    if (desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please provide a description of the danger zone'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await FirebaseFirestore.instance.collection('dangerzones').add({
        'lat': _selectedPosition!.latitude,
        'lng': _selectedPosition!.longitude,
        'radius': _radius,
        'description': desc,
        'reportedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Danger zone reported successfully! Thank you for keeping others safe.'),
          backgroundColor: Colors.green,
          action: SnackBarAction(
            label: 'OK',
            textColor: Colors.white,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to report danger zone: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Modern gradient background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF8F5FE8),
                  Color(0xFFE9E4F6),
                  Color(0xFFF8F9FF),
                ],
              ),
            ),
          ),
          
          // Content
          Column(
            children: [
              // Modern App Bar
              _buildModernAppBar(),
              
              // Main Content
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            _buildMapCard(),
                            const SizedBox(height: 20),
                            _buildDescriptionCard(),
                            const SizedBox(height: 20),
                            _buildRadiusCard(),
                            const SizedBox(height: 20),
                            _buildActionButtons(),
                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModernAppBar() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 16,
        left: 24,
        right: 24,
        bottom: 16,
      ),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'Report Danger Zone',
              style: GoogleFonts.lato(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.red,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Describe the Danger Zone',
                  style: GoogleFonts.lato(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF232946),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Help others stay safe by describing what makes this area dangerous.',
              style: GoogleFonts.lato(
                fontSize: 14,
                color: const Color(0xFF777B84),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'e.g., High crime area, Poor lighting, Construction zone, etc.',
                hintStyle: GoogleFonts.lato(
                  color: const Color(0xFFB7BBC1),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF8F5FE8), width: 2),
                ),
                filled: true,
                fillColor: const Color(0xFFF8F9FF),
              ),
              style: GoogleFonts.lato(
                fontSize: 14,
                color: const Color(0xFF232946),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8F5FE8).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.map_rounded,
                    color: Color(0xFF8F5FE8),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Select Location',
                  style: GoogleFonts.lato(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF232946),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Tap on the map to select the center of the danger zone.',
              style: GoogleFonts.lato(
                fontSize: 14,
                color: const Color(0xFF777B84),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              height: 300,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.withOpacity(0.3)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: GoogleMap(
                  onMapCreated: _onMapCreated,
                  onTap: _onMapTap,
                  initialCameraPosition: CameraPosition(
                    target: _selectedPosition ?? const LatLng(6.9271, 79.8612), // Colombo default
                    zoom: 16.0,
                  ),
                  markers: _markers,
                  circles: _circles,
                  mapType: MapType.normal,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  zoomControlsEnabled: true,
                  scrollGesturesEnabled: true,
                  zoomGesturesEnabled: true,
                  tiltGesturesEnabled: true,
                  rotateGesturesEnabled: true,
                ),
              ),
            ),
            if (_selectedPosition != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF8F5FE8).withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      color: Color(0xFF8F5FE8),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Lat: ${_selectedPosition!.latitude.toStringAsFixed(6)}, Lng: ${_selectedPosition!.longitude.toStringAsFixed(6)}',
                        style: GoogleFonts.lato(
                          fontSize: 12,
                          color: const Color(0xFF777B84),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRadiusCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.radio_button_unchecked,
                    color: Colors.orange,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Danger Zone Radius',
                  style: GoogleFonts.lato(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF232946),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Adjust the radius to cover the dangerous area.',
              style: GoogleFonts.lato(
                fontSize: 14,
                color: const Color(0xFF777B84),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _radius,
                    min: 10,
                    max: 200,
                    divisions: 38,
                    activeColor: const Color(0xFF8F5FE8),
                    inactiveColor: const Color(0xFF8F5FE8).withOpacity(0.3),
                    onChanged: (val) {
                      setState(() {
                        _radius = val;
                        _updateMapMarkers();
                        _updateDangerZone();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8F5FE8).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${_radius.toStringAsFixed(0)}m',
                    style: GoogleFonts.lato(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF8F5FE8),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _currentPosition != null && _selectedPosition != _currentPosition
                ? () {
                    setState(() {
                      _selectedPosition = _currentPosition;
                      _updateMapMarkers();
                      _updateDangerZone();
                    });
                    _mapController?.animateCamera(
                      CameraUpdate.newLatLngZoom(_currentPosition!, 16.0),
                    );
                  }
                : null,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: const BorderSide(color: Color(0xFF8F5FE8)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.my_location,
                  color: Color(0xFF8F5FE8),
                  size: 18,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Current Location',
                    style: GoogleFonts.lato(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF8F5FE8),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : _submitDangerZone,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: _isSubmitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Report Danger Zone',
                          style: GoogleFonts.lato(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
