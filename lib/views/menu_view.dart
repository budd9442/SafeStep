import 'package:flutter/material.dart';
import 'package:safestep/views/fake_call_view.dart';
import 'package:safestep/views/close_contacts_view.dart';
import 'package:safestep/views/safe_chat_view.dart';
import 'package:safestep/views/report_danger_zone_view.dart';
import 'package:safestep/views/about_us_view.dart';
import 'package:safestep/views/debug_screen.dart';
import 'package:safestep/views/activity_monitor_view.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// --- Primary Theme Colors (Refined for Elegance & Clarity) ---
const Color _primaryViolet = Color(0xFF8F5FE8);     // Main theme violet
const Color _lightViolet = Color(0xFFD1C4E9);       // Soft violet background mid-tone
const Color _cardSurface = Colors.white;            // Crisp white card background
const Color _darkText = Color(0xFF232946);          // Dark, readable text
const Color _subtleAccent = Color(0xFFF3EFFF);      // Very light background accent

class MenuView extends StatefulWidget {
  final ValueChanged<bool>? onFeatureOpen;
  final void Function(LatLng, double)? onAddDangerZone;
  final LatLng? currentPosition;
  const MenuView({super.key, this.onFeatureOpen, this.onAddDangerZone, this.currentPosition});

  @override
  State<MenuView> createState() => _MenuViewState();
}

class _MenuViewState extends State<MenuView> with TickerProviderStateMixin {
  Widget? _selectedFeature;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

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

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Container(
          // THEME BACKGROUND: Soft violet gradient
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFB39DDB),
                _lightViolet,
                Color(0xFFF8F9FF),
              ],
            ),
          ),
          child: SafeArea(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // --- Header (Safety Tools Card) ---
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF8F5FE8),
                            Color(0xFFD1C4E9),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.10),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Material(
                              color: Colors.white.withOpacity(0.18),
                              shape: const CircleBorder(),
                              elevation: 0,
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () => Navigator.of(context).maybePop(),
                                child: const Padding(
                                  padding: EdgeInsets.all(10.0),
                                  child: Icon(Icons.arrow_back, color: Colors.white, size: 28),
                                ),
                              ),
                            ),
                            const SizedBox(width: 18),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Text(
                                    'Safety Tools',
                                    style: TextStyle(
                                      fontSize: 30,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      letterSpacing: -1.0,
                                      shadows: [
                                        Shadow(
                                          color: Color(0x33000000),
                                          blurRadius: 6,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // --- Feature Grid ---
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.85,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    delegate: SliverChildListDelegate([
                      _ElegantMenuCard(
                        icon: Icons.call_end,
                        label: 'Fake Call',
                        subtitle: 'Simulate incoming call to exit a situation.',
                        iconColor: const Color(0xFF667eea), // Call Gradient Start
                        onTap: () => _openFeature(const FakeCallView()),
                      ),
                      _ElegantMenuCard(
                        icon: Icons.warning_amber_rounded,
                        label: 'Report Danger',
                        subtitle: 'Mark unsafe areas on the map for community.',
                        iconColor: const Color(0xFFf093fb), // Report Gradient Start
                        onTap: () => _openFeature(ReportDangerZoneView(
                          currentPosition: widget.currentPosition,
                          onDangerZoneChanged: widget.onAddDangerZone,
                        )),
                      ),
                    ]),
                  ),
                ),

                // --- Secondary Grid ---
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.85,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    delegate: SliverChildListDelegate([
                      _ElegantMenuCard(
                        icon: Icons.chat_bubble_outline_rounded,
                        label: 'SafeChat AI',
                        subtitle: 'AI-powered chat for tips and guided safety actions.',
                        iconColor: const Color(0xFF4facfe), // Chat Gradient Start
                        onTap: () => _openFeature(const SafeChatView()),
                      ),
                      _ElegantMenuCard(
                        icon: Icons.people_alt_outlined,
                        label: 'Close Contacts',
                        subtitle: 'Manage and share your location with trusted people.',
                        iconColor: const Color(0xFF43e97b), // Contacts Gradient Start
                        onTap: () => _openFeature(const CloseContactsView()),
                      ),
                    ]),
                  ),
                ),

                // Bottom spacing
                const SliverToBoxAdapter(
                  child: SizedBox(height: 50),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- The "Elegance & Clarity" User-Friendly Card Widget ---
class _ElegantMenuCard extends StatefulWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color iconColor; // Single accent color for simplicity
  final VoidCallback onTap;

  const _ElegantMenuCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.iconColor,
    required this.onTap,
  });

  @override
  State<_ElegantMenuCard> createState() => _ElegantMenuCardState();
}

class _ElegantMenuCardState extends State<_ElegantMenuCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _shadowElevation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    // Subtle press-in animation
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    // Shadow lift animation
    _shadowElevation = Tween<double>(begin: 12.0, end: 3.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            // ELEGANCE & CLARITY DESIGN: Crisp white card body
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: _cardSurface, 
              border: Border.all(color: Colors.grey.shade100, width: 1.0),
              boxShadow: [
                // Soft, clean lift shadow
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: _shadowElevation.value,
                  offset: const Offset(0, 5),
                ),
                // Subtle colored inner glow/ring (WOW factor)
                BoxShadow(
                  color: widget.iconColor.withOpacity(0.4),
                  blurRadius: 20, 
                  spreadRadius: -12,
                  offset: const Offset(0, 0),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: widget.onTap,
                onTapDown: (_) => _controller.forward(),
                onTapUp: (_) => _controller.reverse(),
                onTapCancel: () => _controller.reverse(),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      // ICON: Vibrant, highly focused icon ring
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.iconColor.withOpacity(0.15),
                          border: Border.all(color: widget.iconColor.withOpacity(0.4), width: 1.5),
                        ),
                        child: Icon(
                          widget.icon,
                          color: widget.iconColor,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Text content (Optimal Readability)
                      Text(
                        widget.label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _darkText,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.subtitle,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}