import 'package:flutter/material.dart';
import 'package:safestep/views/fake_call_view.dart';
import 'package:safestep/views/close_contacts_view.dart';
import 'package:safestep/views/safe_chat_view.dart';
import 'package:safestep/views/report_danger_zone_view.dart';
import 'package:safestep/views/about_us_view.dart';
import 'package:safestep/views/debug_screen.dart';
import 'package:safestep/views/activity_monitor_view.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MenuView extends StatefulWidget {
  final ValueChanged<bool>? onFeatureOpen;
  final void Function(LatLng, double)? onAddDangerZone;
  final LatLng? currentPosition;
  const MenuView({super.key, this.onFeatureOpen, this.onAddDangerZone, this.currentPosition});

  @override
  State<MenuView> createState() => _MenuViewState();
}

class _MenuViewState extends State<MenuView> {
  Widget? _selectedFeature;

  void _openFeature(Widget feature) {
    setState(() {
      _selectedFeature = feature;
    });
    widget.onFeatureOpen?.call(true);
  }

  void _closeFeature() {
    setState(() {
      _selectedFeature = null;
    });
    widget.onFeatureOpen?.call(false);
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedFeature != null) {
      return _selectedFeature!;
    }
    return Padding(
      padding: const EdgeInsets.all(18.0),
      child: GridView.count(
        crossAxisCount: 2,
        crossAxisSpacing: 18,
        mainAxisSpacing: 18,
        childAspectRatio: 1.1,
        children: [
          _MenuTile(
            icon: Icons.call,
            label: 'Fake Call',
            color: const Color(0xFF8F5FE8),
            onTap: () => _openFeature(const FakeCallView()),
          ),
          _MenuTile(
            icon: Icons.contacts,
            label: 'Close Contacts',
            color: const Color(0xFF6C63FF),
            onTap: () => _openFeature(const CloseContactsView()),
          ),
          _MenuTile(
            icon: Icons.chat_bubble_outline,
            label: 'SafeChat',
            color: const Color(0xFFE0006A),
            onTap: () => _openFeature(const SafeChatView()),
          ),
          _MenuTile(
            icon: Icons.report_gmailerrorred,
            label: 'Report Danger',
            color: const Color(0xFF232946),
            onTap: () => _openFeature(ReportDangerZoneView(
              currentPosition: widget.currentPosition,
              onDangerZoneChanged: widget.onAddDangerZone,
            )),
          ),
          _MenuTile(
            icon: Icons.info_outline,
            label: 'About Us',
            color: const Color(0xFF8F5FE8),
            onTap: () => _openFeature(const AboutUsView()),
          ),
          _MenuTile(
            icon: Icons.bug_report,
            label: 'Debug',
            color: const Color(0xFF6C63FF),
            onTap: () => _openFeature(const ActivityMonitorView()),
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _MenuTile({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      elevation: 3,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(18),
                child: Icon(icon, color: color, size: 36),
              ),
              const SizedBox(height: 18),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: color,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
